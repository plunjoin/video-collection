import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:http/http.dart' as http;

import '../models/video_model.dart';

/// 构建正式包时通过 `--dart-define=API_BASE_URL=https://api.example.com` 写入。
const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// 正式包固定使用构建时写入的地址，调试包才允许在设置里修改。
bool get allowsApiBaseUrlOverride => !kReleaseMode;

String resolveApiBaseUrl({
  required bool releaseMode,
  required String definedUrl,
  required bool androidEmulator,
}) {
  final defined = definedUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (releaseMode || defined.isNotEmpty) return defined;
  if (androidEmulator) return 'http://10.0.2.2:80';
  return 'http://127.0.0.1:80';
}

/// Android 模拟器访问宿主机请用 10.0.2.2；桌面 / iOS 模拟器用 127.0.0.1。
/// 正式包只读取 [configuredApiBaseUrl]。
String resolveDefaultApiBaseUrl() {
  return resolveApiBaseUrl(
    releaseMode: kReleaseMode,
    definedUrl: configuredApiBaseUrl,
    androidEmulator: !kIsWeb && Platform.isAndroid,
  );
}

/// 把本机地址改写成当前平台可访问的形式
String normalizeApiBaseUrlForPlatform(String url) {
  final trimmed = url.trim();
  if (kIsWeb || !Platform.isAndroid) return trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return trimmed;
  if (uri.host != '127.0.0.1' && uri.host != 'localhost') return trimmed;

  return uri.replace(host: '10.0.2.2').toString();
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  ApiService.withClient(http.Client client) : _client = client;

  http.Client _client = http.Client();
  String? token;

  Future<Map<String, dynamic>> userRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    request.headers['Accept'] = 'application/json';
    request.headers['Content-Type'] = 'application/json';
    if (authenticated && token != null) {
      request.headers['Authorization'] = 'Bearer $token';
      // The existing logout endpoint invalidates the cookie session.
      request.headers['Cookie'] = 'agg_auth_token=$token';
    }
    if (body != null) request.body = json.encode(body);
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 10));
      final data =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode >= 400 || data['code'] != 1) {
        throw ApiException(
          data['error']?.toString() ?? data['msg']?.toString() ?? '请求失败，请稍后重试',
          response.statusCode,
        );
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('无法连接服务器，请检查网络和服务端地址');
    }
  }

  String _baseUrl = resolveDefaultApiBaseUrl();

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    if (url.endsWith('/')) {
      _baseUrl = url.substring(0, url.length - 1);
    } else {
      _baseUrl = url;
    }
  }

  Future<bool> testConnection(String testUrl) async {
    try {
      final cleanUrl = testUrl.endsWith('/')
          ? testUrl.substring(0, testUrl.length - 1)
          : testUrl;
      final uri = Uri.parse('$cleanUrl/api/categories');
      final res = await _client.get(uri).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 1. 获取视频列表
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int pageSize = 24,
    int? typeId,
    String? keyword,
    String? area,
    String? year,
    String? sort,
  }) async {
    try {
      final queryParameters = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };
      if (typeId != null && typeId > 0) {
        queryParameters['type_id'] = typeId.toString();
      }
      if (keyword != null && keyword.trim().isNotEmpty) {
        queryParameters['keyword'] = keyword.trim();
      }
      if (area != null && area != '全部') {
        queryParameters['area'] = area;
      }
      if (year != null && year != '全部') {
        queryParameters['year'] = year;
      }
      if (sort != null && sort != 'time') {
        queryParameters['sort'] = sort;
      }

      final uri = Uri.parse('$_baseUrl/api/videos')
          .replace(queryParameters: queryParameters);
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if ((decoded['code'] == 1 || decoded['code'] == 200) &&
            decoded['data'] != null) {
          final listData = decoded['data'] as List;
          List<VideoRecord> list = [];
          for (var item in listData) {
            final v = VideoRecord.fromJson(Map<String, dynamic>.from(item));
            list.add(v);
          }
          return {'total': decoded['total'] ?? list.length, 'list': list};
        }
      }
    } catch (_) {}

    return {'total': 0, 'list': <VideoRecord>[]};
  }

  // 2. 获取视频详情
  Future<Map<String, dynamic>> getVideoDetail(int id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/video?id=$id');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 1 && decoded['data'] != null) {
          final video = VideoRecord.fromJson(
            Map<String, dynamic>.from(decoded['data']),
          );
          List<VideoRecord> related = [];
          if (decoded['related'] is List) {
            for (var item in decoded['related']) {
              related.add(
                VideoRecord.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
          return {'video': video, 'related': related};
        }
      }
    } catch (_) {}

    return {'video': null, 'related': <VideoRecord>[]};
  }

  // 3. 获取排行榜
  Future<Map<String, List<VideoRecord>>> getRankings() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/rankings?limit=10');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 1) {
          List<VideoRecord> parseList(dynamic raw) {
            if (raw is List) {
              return raw
                  .map(
                    (item) =>
                        VideoRecord.fromJson(Map<String, dynamic>.from(item)),
                  )
                  .toList();
            }
            return [];
          }

          final anime = parseList(decoded['anime']);
          final top = parseList(decoded['top']);
          return {
            // The server returns independent overall and anime lists. Keeping
            // them separate avoids presenting the anime list as the overall rank.
            'top': top,
            'anime': anime,
          };
        }
      }
    } catch (_) {}

    return {'top': <VideoRecord>[], 'anime': <VideoRecord>[]};
  }

  // 4. 获取分类列表
  Future<List<Category>> getCategories() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/categories');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 1 && decoded['data'] is List) {
          List<Category> list = [];
          for (var item in decoded['data']) {
            list.add(Category.fromJson(Map<String, dynamic>.from(item)));
          }
          final animeCategories = list
              .where((c) => c.id == 4 || c.pid == 4 || c.name.contains('动漫'))
              .toList();
          if (animeCategories.isNotEmpty) {
            return animeCategories;
          }
          return list;
        }
      }
    } catch (_) {}

    return [];
  }

  // 5. 获取最新更新。新番页只请求动漫总类，并再滤掉电影、电视剧等非番剧。
  Future<Map<String, List<VideoRecord>>> getLatest() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/latest')
          .replace(queryParameters: {'type_id': '4'});
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 1) {
          List<VideoRecord> parseList(dynamic raw) {
            if (raw is List) {
              return raw
                  .map(
                    (item) =>
                        VideoRecord.fromJson(Map<String, dynamic>.from(item)),
                  )
                  .where((video) => video.isAnime)
                  .toList();
            }
            return [];
          }

          return {
            'today': parseList(decoded['today']),
            'yesterday': parseList(decoded['yesterday']),
            'earlier': parseList(decoded['earlier']),
          };
        }
      }
    } catch (_) {}

    return {
      'today': <VideoRecord>[],
      'yesterday': <VideoRecord>[],
      'earlier': <VideoRecord>[],
    };
  }

  // 6. 播放打点
  Future<void> hitVideo(int id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/video/hit?id=$id');
      await _client.post(uri).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // 7. 站点全局配置
  Future<SiteConfig> getSiteConfig() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/site/config');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 1 && decoded['data'] is Map) {
          final data = Map<String, dynamic>.from(decoded['data']);
          List<FriendLink> links = [];
          if (data['site_friend_links'] != null) {
            try {
              final rawLinks = json.decode(data['site_friend_links']);
              if (rawLinks is List) {
                links = rawLinks
                    .map(
                      (item) =>
                          FriendLink.fromJson(Map<String, dynamic>.from(item)),
                    )
                    .toList();
              }
            } catch (_) {}
          }
          final def = SiteConfig.defaultConfig();
          return SiteConfig(
            siteName: data['site_name']?.toString() ?? def.siteName,
            siteSubtitle: data['site_subtitle']?.toString() ?? def.siteSubtitle,
            siteAnnouncement:
                data['site_announcement']?.toString() ?? def.siteAnnouncement,
            siteKeywords: data['site_keywords']?.toString() ?? def.siteKeywords,
            siteDescription:
                data['site_description']?.toString() ?? def.siteDescription,
            siteContactEmail:
                data['site_contact_email']?.toString() ?? def.siteContactEmail,
            siteContactGroup:
                data['site_contact_group']?.toString() ?? def.siteContactGroup,
            siteDisclaimer:
                data['site_disclaimer']?.toString() ?? def.siteDisclaimer,
            friendLinks: links.isNotEmpty ? links : def.friendLinks,
          );
        }
      }
    } catch (_) {}

    return SiteConfig.defaultConfig();
  }

  /// 搜索建议与热搜。关键词为空时，服务端返回站点热搜词。
  Future<Map<String, dynamic>> getSearchSuggestions({
    String keyword = '',
    int limit = 8,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search/suggest').replace(
        queryParameters: {
          'keyword': keyword.trim(),
          'limit': limit.clamp(1, 10).toString(),
        },
      );
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return {'suggestions': <String>[], 'hot': keyword.trim().isEmpty};
      }
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : <String, dynamic>{};
      final raw = data['suggestions'];
      return {
        'suggestions': raw is List
            ? raw
                  .map((item) => item.toString())
                  .where((item) => item.isNotEmpty)
                  .toList()
            : <String>[],
        'hot': data['hot'] == true,
      };
    } catch (_) {
      return {'suggestions': <String>[], 'hot': keyword.trim().isEmpty};
    }
  }

  /// 登录后读取基于收藏和播放历史的个性化推荐。
  Future<Map<String, dynamic>> getPersonalizedRecommendations({
    int limit = 12,
  }) async {
    try {
      final response = await userRequest(
        '/api/recommend/for-you?limit=${limit.clamp(4, 30)}',
      );
      final data = response['data'] is Map
          ? Map<String, dynamic>.from(response['data'] as Map)
          : <String, dynamic>{};
      final raw = data['items'];
      final items = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) =>
                      VideoRecord.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : <VideoRecord>[];
      return {
        'list': items,
        'personalized': data['personalized'] == true,
        'basedOn': data['based_on'] is List
            ? List<String>.from(data['based_on'] as List)
            : <String>[],
      };
    } catch (_) {
      return {
        'list': <VideoRecord>[],
        'personalized': false,
        'basedOn': <String>[],
      };
    }
  }

  /// 获取资讯或社区动态列表。社区列表会在有登录态时返回 liked 状态。
  Future<Map<String, dynamic>> getContentFeed({
    required String kind,
    int page = 1,
    int pageSize = 20,
  }) async {
    final path = kind == 'news' ? '/api/news' : '/api/community/posts';
    final response = await userRequest(
      '$path?page=$page&page_size=${pageSize.clamp(1, 100)}',
    );
    final raw = response['data'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    return {
      'list': items,
      'total': response['total'] is int
          ? response['total'] as int
          : items.length,
    };
  }

  /// 获取资讯或社区动态详情。
  Future<Map<String, dynamic>> getContentDetail({
    required String kind,
    required int id,
  }) async {
    final path = kind == 'news' ? '/api/news' : '/api/community/posts';
    final response = await userRequest('$path?id=$id');
    final data = response['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// 获取社区动态评论。
  Future<Map<String, dynamic>> getCommunityComments({
    required int postId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await userRequest(
      '/api/community/comments?post_id=$postId&page=$page&page_size=${pageSize.clamp(1, 100)}',
    );
    final raw = response['data'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    return {
      'list': items,
      'total': response['total'] is int
          ? response['total'] as int
          : items.length,
    };
  }

  /// 发布社区动态；服务端可能会进入审核队列，调用方应展示服务端 msg。
  Future<Map<String, dynamic>> createCommunityPost({
    required String title,
    required String content,
    String category = '',
  }) => userRequest(
    '/api/community/posts',
    method: 'POST',
    body: {'title': title, 'content': content, 'category': category},
  );

  /// 发布社区评论。
  Future<Map<String, dynamic>> createCommunityComment({
    required int postId,
    required String content,
  }) => userRequest(
    '/api/community/comments',
    method: 'POST',
    body: {'post_id': postId, 'content': content},
  );

  /// 点赞或取消点赞社区动态。
  Future<Map<String, dynamic>> setCommunityPostLike({
    required int postId,
    required bool liked,
  }) => userRequest(
    liked ? '/api/community/likes' : '/api/community/likes?post_id=$postId',
    method: liked ? 'POST' : 'DELETE',
    body: liked ? {'post_id': postId} : null,
  );

  /// 通用评论列表。`targetType` 为 video、news 或 post。
  Future<Map<String, dynamic>> listComments({
    required String targetType,
    required int targetId,
    int page = 1,
    int pageSize = 20,
    int rootId = 0,
  }) async {
    final query = <String, String>{
      'target_type': targetType,
      'target_id': '$targetId',
      'page': '$page',
      'page_size': '${pageSize.clamp(1, 100)}',
    };
    if (rootId > 0) query['root_id'] = '$rootId';
    final path = Uri(path: '/api/comments', queryParameters: query).toString();
    final response = await userRequest(path, authenticated: token != null);
    return _commentPage(response);
  }

  /// 发表评论或回复。未登录会由服务端返回 401。
  Future<Map<String, dynamic>> createComment({
    required String targetType,
    required int targetId,
    required String content,
    int parentId = 0,
  }) => userRequest(
    '/api/comments',
    method: 'POST',
    body: {
      'target_type': targetType,
      'target_id': targetId,
      'content': content,
      if (parentId > 0) 'parent_id': parentId,
    },
  );

  Future<Map<String, dynamic>> deleteComment(int id) =>
      userRequest('/api/comments?id=$id', method: 'DELETE');

  Future<List<Map<String, dynamic>>> listDanmaku({
    required int videoId,
    required String episodeKey,
  }) async {
    final path = Uri(
      path: '/api/danmaku',
      queryParameters: {'video_id': '$videoId', 'episode_key': episodeKey},
    ).toString();
    final response = await userRequest(path, authenticated: token != null);
    final raw = response['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> sendDanmaku({
    required int videoId,
    required String episodeKey,
    required int playTimeMs,
    required int mode,
    required String color,
    required String content,
  }) async {
    final response = await userRequest(
      '/api/danmaku',
      method: 'POST',
      body: {
        'video_id': videoId,
        'episode_key': episodeKey,
        'play_time_ms': playTimeMs,
        'mode': mode,
        'color': color,
        'content': content,
      },
    );
    final data = response['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException('弹幕发送失败');
  }

  Future<void> deleteDanmaku(int id) =>
      userRequest('/api/danmaku?id=$id', method: 'DELETE');

  Future<Map<String, dynamic>> setCommentLike({
    required int commentId,
    required bool liked,
  }) => userRequest(
    liked ? '/api/comments/likes' : '/api/comments/likes?comment_id=$commentId',
    method: liked ? 'POST' : 'DELETE',
    body: liked ? {'comment_id': commentId} : null,
  );

  Map<String, dynamic> _commentPage(Map<String, dynamic> response) {
    final raw = response['data'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    return {
      'list': items,
      'total': response['total'] is int
          ? response['total'] as int
          : items.length,
      'msg': response['msg']?.toString() ?? '',
      'data': response['data'],
    };
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}
