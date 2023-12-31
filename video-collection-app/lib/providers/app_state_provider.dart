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

  PlayHistoryItem({
    required this.videoId,
    required this.videoName,
    required this.videoPicture,
    required this.episodeName,
    required this.playerCode,
    required this.playUrl,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'videoName': videoName,
    'videoPicture': videoPicture,
    'episodeName': episodeName,
    'playerCode': playerCode,
    'playUrl': playUrl,
    'timestamp': timestamp,
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
      );
}

class AppStateProvider extends ChangeNotifier {
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

  AppStateProvider() {
    _loadFromPreferences();
  }

  Future<void> _loadFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();

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
      ApiService().setBaseUrl(_apiBaseUrl);
    } else {
      _apiBaseUrl = resolveDefaultApiBaseUrl();
      ApiService().setBaseUrl(_apiBaseUrl);
    }

    // 3. 追番收藏
    final favListJson = prefs.getStringList('favorite_videos') ?? [];
    _favoriteVideos.clear();
    for (var item in favListJson) {
      try {
        final decoded = json.decode(item);
        _favoriteVideos.add(VideoRecord.fromJson(decoded));
      } catch (_) {}
    }

    // 4. 播放历史
    final histListJson = prefs.getStringList('play_history') ?? [];
    _playHistory.clear();
    for (var item in histListJson) {
      try {
        final decoded = json.decode(item);
        _playHistory.add(PlayHistoryItem.fromJson(decoded));
      } catch (_) {}
    }

    // 5. 搜索历史
    _searchHistory = prefs.getStringList('search_history') ?? [];

    _isInitialized = true;
    notifyListeners();

    // 加载全局配置
    fetchSiteConfig();
  }

  Future<void> fetchSiteConfig() async {
    _siteConfig = await ApiService().getSiteConfig();
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
    final ok = await ApiService().testConnection(normalized);
    _apiBaseUrl = normalized;
    ApiService().setBaseUrl(normalized);
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
    final index = _favoriteVideos.indexWhere((v) => v.id == video.id);
    if (index >= 0) {
      _favoriteVideos.removeAt(index);
    } else {
      _favoriteVideos.insert(0, video);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final list = _favoriteVideos.map((v) => json.encode(v.toJson())).toList();
    await prefs.setStringList('favorite_videos', list);
  }

  // 记录播放历史
  Future<void> addPlayHistory({
    required VideoRecord video,
    required String episodeName,
    required String playerCode,
    required String playUrl,
  }) async {
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
      ),
    );
    if (_playHistory.length > 50) {
      _playHistory.removeLast();
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final list = _playHistory
        .map((item) => json.encode(item.toJson()))
        .toList();
    await prefs.setStringList('play_history', list);

    // 触发后端播放统计
    ApiService().hitVideo(video.id);
  }

  Future<void> clearPlayHistory() async {
    _playHistory.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('play_history');
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
