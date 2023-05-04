import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_model.dart';
import '../services/api_service.dart';

class PlayHistoryItem {
  final int videoId;
  final String videoName;
  final String videoPicture;
  final String episodeName;
  final String playerCode;
  final String playUrl;
  final int timestamp;
  final int routeIndex;
  final int episodeIndex;
  final int currentTime;
  final int duration;

  PlayHistoryItem({
    required this.videoId,
    required this.videoName,
    required this.videoPicture,
    required this.episodeName,
    required this.playerCode,
    required this.playUrl,
    required this.timestamp,
    this.routeIndex = 0,
    this.episodeIndex = 0,
    this.currentTime = 0,
    this.duration = 0,
  });

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'videoName': videoName,
    'videoPicture': videoPicture,
    'episodeName': episodeName,
    'playerCode': playerCode,
    'playUrl': playUrl,
    'timestamp': timestamp,
    'routeIndex': routeIndex,
    'episodeIndex': episodeIndex,
    'currentTime': currentTime,
    'duration': duration,
  };

  factory PlayHistoryItem.fromJson(Map<String, dynamic> json) =>
      PlayHistoryItem(
        videoId: json['videoId'] ?? 0,
        videoName: json['videoName'] ?? '',
        videoPicture: json['videoPicture'] ?? '',
        episodeName: json['episodeName'] ?? '',
        playerCode: json['playerCode'] ?? '',
        playUrl: json['playUrl'] ?? '',
        timestamp: json['timestamp'] ?? 0,
        routeIndex: json['routeIndex'] ?? 0,
        episodeIndex: json['episodeIndex'] ?? 0,
        currentTime: json['currentTime'] ?? 0,
        duration: json['duration'] ?? 0,
      );

  Map<String, dynamic> toCloud() => {
    'video_id': videoId,
    'video_name': videoName,
    'picture': videoPicture,
    'episode_name': episodeName,
    'route_index': routeIndex,
    'episode_index': episodeIndex,
    'current_time': currentTime,
    'duration': duration,
    'progress': duration > 0 ? currentTime / duration * 100 : 0,
  };
}

class AppStateProvider extends ChangeNotifier {
  final ApiService _api;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _user != null;
  bool _syncing = false;
  int? _syncGeneration;
  bool get syncing => _syncing;
  String? _accountError;
  String? get accountError => _accountError;
  int _accountGeneration = 0;
  int _libraryRevision = 0;
  final Set<int> _favoriteRequests = {};
  final Set<int> _pendingHistory = {};
  bool _disposed = false;
  String _accent = 'blue';
  String get accent => _accent;
  Color get accentColor => switch (_accent) {
    'pink' => const Color(0xFFC64C91),
    'purple' => const Color(0xFF8464D4),
    _ => const Color(0xFF597BEA),
  };
  ThemeMode _themeMode = ThemeMode.light;
  String _apiBaseUrl = resolveDefaultApiBaseUrl();
  final List<VideoRecord> _favoriteVideos = [];
  final List<PlayHistoryItem> _playHistory = [];
  List<String> _searchHistory = [];
  SiteConfig _siteConfig = SiteConfig.defaultConfig();
  bool _isInitialized = false;

  ThemeMode get themeMode => _themeMode;
  String get apiBaseUrl => _apiBaseUrl;
  List<VideoRecord> get favoriteVideos => _favoriteVideos;
  List<PlayHistoryItem> get playHistory => _playHistory;
  List<String> get searchHistory => _searchHistory;
  SiteConfig get siteConfig => _siteConfig;
  bool get isInitialized => _isInitialized;

  AppStateProvider({ApiService? api}) : _api = api ?? ApiService() {
    _loadFromPreferences();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String get _libraryKey => isLoggedIn
      ? '${Uri.encodeComponent(_apiBaseUrl)}_${_user!['id']}'
      : 'guest';

  Future<void> _saveLibrary() async {
    final key = _libraryKey;
    final favorites = _favoriteVideos
        .map((v) => json.encode(v.toJson()))
        .toList();
    final history = _playHistory.map((v) => json.encode(v.toJson())).toList();
    final pending = _pendingHistory.map((id) => id.toString()).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites_$key', favorites);
    await prefs.setStringList('history_$key', history);
    await prefs.setStringList('pending_history_$key', pending);
  }

  Future<void> _restoreLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _libraryKey;
    _pendingHistory
      ..clear()
      ..addAll(
        (prefs.getStringList('pending_history_$key') ?? [])
            .map(int.tryParse)
            .whereType<int>(),
      );
    _favoriteVideos.clear();
    _playHistory.clear();
    for (final raw
        in prefs.getStringList('favorites_$key') ??
            (isLoggedIn ? [] : prefs.getStringList('favorite_videos') ?? [])) {
      try {
        _favoriteVideos.add(VideoRecord.fromJson(json.decode(raw)));
      } catch (_) {}
    }
    for (final raw
        in prefs.getStringList('history_$key') ??
            (isLoggedIn ? [] : prefs.getStringList('play_history') ?? [])) {
      try {
        _playHistory.add(PlayHistoryItem.fromJson(json.decode(raw)));
      } catch (_) {}
    }
  }

  Future<void> authenticate(
    String username,
    String password, {
    String? nickname,
  }) async {
    final generation = _accountGeneration;
    final result = await _api.userRequest(
      nickname == null ? '/api/login' : '/api/register',
      method: 'POST',
      authenticated: false,
      body: {
        'username': username.trim(),
        'password': password,
        if (nickname != null) 'nickname': nickname.trim(),
      },
    );
    if (generation != _accountGeneration) return;
    _accountGeneration++;
    _api.token = result['token'] as String;
    _user = Map<String, dynamic>.from(result['user']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_token', _api.token!);
    await prefs.setString('account_user', json.encode(_user));
    await _restoreLibrary();
    notifyListeners();
    await syncAccount();
  }

  Future<void> logout({bool notifyServer = true}) async {
    _accountGeneration++;
    _syncing = false;
    if (notifyServer && _api.token != null) {
      try {
        await _api.userRequest('/api/logout', method: 'POST');
      } catch (_) {}
    }
    _api.token = null;
    _user = null;
    _accountError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('account_token');
    await prefs.remove('account_user');
    await _restoreLibrary();
    notifyListeners();
  }

  Future<void> syncAccount() async {
    if (!isLoggedIn || (_syncing && _syncGeneration == _accountGeneration)) {
      return;
    }
    final generation = _accountGeneration;
    final revision = _libraryRevision;
    _syncing = true;
    _syncGeneration = generation;
    _accountError = null;
    notifyListeners();
    try {
      final me = await _api.userRequest('/api/me');
      if (generation != _accountGeneration) return;
      final favorites = await _api.userRequest('/api/user/favorites');
      if (generation != _accountGeneration) return;
      final history = await _api.userRequest('/api/user/history');
      if (generation != _accountGeneration || revision != _libraryRevision) {
        return;
      }
      final mergedHistory = <int, PlayHistoryItem>{};
      for (final v in history['data'] as List) {
        final item = PlayHistoryItem(
          videoId: v['video_id'],
          videoName: v['video_name'] ?? '',
          videoPicture: v['picture'] ?? '',
          episodeName: v['episode_name'] ?? '',
          playerCode: '',
          playUrl: '',
          timestamp:
              DateTime.tryParse(v['updated_at']?.toString() ?? '')
                  ?.millisecondsSinceEpoch ??
              0,
          routeIndex: v['route_index'] ?? 0,
          episodeIndex: v['episode_index'] ?? 0,
          currentTime: v['current_time'] ?? 0,
          duration: v['duration'] ?? 0,
        );
        mergedHistory[item.videoId] = item;
      }
      // Retry newer local progress after an offline playback session.
      for (final item in List<PlayHistoryItem>.of(_playHistory)) {
        if (!_pendingHistory.contains(item.videoId)) continue;
        if (generation != _accountGeneration || revision != _libraryRevision) {
          return;
        }
        final remote = mergedHistory[item.videoId];
        if (remote == null || item.timestamp > remote.timestamp) {
          await _api.userRequest(
            '/api/user/history',
            method: 'POST',
            body: item.toCloud(),
          );
          mergedHistory[item.videoId] = item;
        }
      }
      if (generation != _accountGeneration || revision != _libraryRevision) {
        return;
      }
      _pendingHistory.clear();
      _user = Map<String, dynamic>.from(me['data']);
      _favoriteVideos
        ..clear()
        ..addAll(
          (favorites['data'] as List).map(
            (v) => VideoRecord.fromJson({
              'id': v['video_id'],
              'name': v['video_name'],
              'picture': v['picture'],
              'remarks': v['remarks'],
            }),
          ),
        );
      _playHistory
        ..clear()
        ..addAll(
          mergedHistory.values.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        );
      await _saveLibrary();
    } on ApiException catch (e) {
      if (generation != _accountGeneration) return;
      if (e.statusCode == 401) await logout(notifyServer: false);
      _accountError = e.statusCode == 401 ? '登录已过期，请重新登录' : e.message;
    } finally {
      if (_syncGeneration == generation) _syncing = false;
      notifyListeners();
    }
  }

  Future<bool> _cloudWrite(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? body,
  }) async {
    if (!isLoggedIn) return true;
    final generation = _accountGeneration;
    try {
      await _api.userRequest(path, method: method, body: body);
      if (generation != _accountGeneration) return false;
      _accountError = null;
      return true;
    } on ApiException catch (e) {
      if (generation != _accountGeneration) return false;
      if (e.statusCode == 401) await logout(notifyServer: false);
      _accountError = e.statusCode == 401 ? '登录已过期，请重新登录' : e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> setAccent(String value) async {
    _accent = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accent', value);
  }

  Future<void> _loadFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _accent = prefs.getString('accent') ?? 'blue';

    // 1. 主题
    final themeStr = prefs.getString('theme_mode') ?? 'light';
    if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeStr == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }

    // 2. API Base URL（Android 模拟器上 127.0.0.1 无法访问宿主机）
    final savedUrl = prefs.getString('api_base_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _apiBaseUrl = normalizeApiBaseUrlForPlatform(savedUrl);
      if (_apiBaseUrl != savedUrl) {
        await prefs.setString('api_base_url', _apiBaseUrl);
      }
      _api.setBaseUrl(_apiBaseUrl);
    } else {
      _apiBaseUrl = resolveDefaultApiBaseUrl();
      _api.setBaseUrl(_apiBaseUrl);
    }

    // 5. 搜索历史
    _searchHistory = prefs.getStringList('search_history') ?? [];

    _api.token = prefs.getString('account_token');
    try {
      _user = json.decode(prefs.getString('account_user') ?? 'null');
    } catch (_) {}
    if (_api.token == null) _user = null;
    await _restoreLibrary();
    _isInitialized = true;
    notifyListeners();

    // 加载全局配置
    fetchSiteConfig();
    syncAccount();
  }

  Future<void> fetchSiteConfig() async {
    _siteConfig = await _api.getSiteConfig();
    notifyListeners();
  }

  // 切换主题
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(
      'theme_mode',
      mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.dark ? 'dark' : 'system'),
    );
  }

  // 修改 API 地址
  Future<bool> updateApiBaseUrl(String newUrl) async {
    final normalized = normalizeApiBaseUrlForPlatform(newUrl);
    final ok = await _api.testConnection(normalized);
    if (!ok) return false;
    if (normalized != _apiBaseUrl) await logout();
    _apiBaseUrl = normalized;
    _api.setBaseUrl(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', normalized);
    fetchSiteConfig();
    notifyListeners();
    return ok;
  }

  // 追番 / 取消追番
  bool isFavorite(int videoId) {
    return _favoriteVideos.any((v) => v.id == videoId);
  }

  Future<void> toggleFavorite(VideoRecord video) async {
    if (!_favoriteRequests.add(video.id)) return;
    final removing = isFavorite(video.id);
    _libraryRevision++;
    try {
      if (!await _cloudWrite(
        removing ? '/api/user/favorites?id=${video.id}' : '/api/user/favorites',
        method: removing ? 'DELETE' : 'POST',
        body: removing
            ? null
            : {
                'video_id': video.id,
                'video_name': video.name,
                'picture': video.picture,
                'remarks': video.remarks,
              },
      )) {
        return;
      }
      _favoriteVideos.removeWhere((v) => v.id == video.id);
      if (!removing) _favoriteVideos.insert(0, video);
      _libraryRevision++;
      notifyListeners();
      await _saveLibrary();
    } finally {
      _favoriteRequests.remove(video.id);
    }
  }

  // 记录播放历史
  Future<void> addPlayHistory({
    required VideoRecord video,
    required String episodeName,
    required String playerCode,
    required String playUrl,
    int routeIndex = 0,
    int episodeIndex = 0,
    int currentTime = 0,
    int duration = 0,
    bool countHit = true,
  }) async {
    final generation = _accountGeneration;
    _libraryRevision++;
    if (isLoggedIn) _pendingHistory.add(video.id);
    _playHistory.removeWhere((item) => item.videoId == video.id);
    _playHistory.insert(
      0,
      PlayHistoryItem(
        videoId: video.id,
        videoName: video.name,
        videoPicture: video.picture,
        episodeName: episodeName,
        playerCode: playerCode,
        playUrl: playUrl,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        routeIndex: routeIndex,
        episodeIndex: episodeIndex,
        currentTime: currentTime,
        duration: duration,
      ),
    );
    if (_playHistory.length > 50) {
      _playHistory.removeLast();
    }
    notifyListeners();
    final entry = _playHistory.first;
    await _saveLibrary();
    if (generation == _accountGeneration) {
      final saved = await _cloudWrite(
        '/api/user/history',
        body: entry.toCloud(),
      );
      if (saved &&
          generation == _accountGeneration &&
          _playHistory.any((item) => identical(item, entry))) {
        _pendingHistory.remove(video.id);
        await _saveLibrary();
      }
    }

    // 触发后端播放统计
    if (countHit) _api.hitVideo(video.id);
  }

  Future<void> clearPlayHistory() async {
    _libraryRevision++;
    if (!await _cloudWrite('/api/user/history?id=all', method: 'DELETE')) {
      return;
    }
    _libraryRevision++;
    _playHistory.clear();
    _pendingHistory.clear();
    notifyListeners();
    await _saveLibrary();
  }

  // 搜索词管理
  Future<void> addSearchKeyword(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    _searchHistory.remove(trimmed);
    _searchHistory.insert(0, trimmed);
    if (_searchHistory.length > 15) {
      _searchHistory.removeLast();
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', _searchHistory);
  }

  Future<void> clearSearchHistory() async {
    _searchHistory.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
  }
}
