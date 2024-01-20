import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/video_model.dart';

/// Android 模拟器访问宿主机请用 10.0.2.2；桌面 / iOS 模拟器用 127.0.0.1
String resolveDefaultApiBaseUrl() {
  if (!kIsWeb && Platform.isAndroid) {
    return 'http://10.0.2.2:80';
  }
  return 'http://127.0.0.1:80';
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
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
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
      final queryParameters = {
        'page': page.toString(),
        'page_size': pageSize.toString(),
        'type_id': (typeId != null && [4, 15, 16, 17].contains(typeId))
            ? typeId.toString()
            : '4',
      };
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
      final res = await http
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
      final res = await http
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
      final res = await http
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
            'top': top.isNotEmpty ? top : anime,
            'anime': anime.isNotEmpty ? anime : top,
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
      final res = await http
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

  // 5. 获取最新更新
  Future<Map<String, List<VideoRecord>>> getLatest() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/latest');
      final res = await http
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
      await http.post(uri).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // 7. 站点全局配置
  Future<SiteConfig> getSiteConfig() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/site/config');
      final res = await http
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
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}
