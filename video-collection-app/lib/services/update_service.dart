import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/update_model.dart';
import 'api_service.dart';

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

class UpdateService {
  static const String currentVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  static const int currentBuildNumber =
      int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 1);
  static const String defaultGitHubRepo = 'plunjoin/video-collection';

  final http.Client _client;
  final ApiService _api;

  UpdateService({http.Client? client, ApiService? api})
      : _client = client ?? http.Client(),
        _api = api ?? ApiService();

  /// 检查客户端是否有可用更新
  /// 优先请求后端自建服务 `/api/app/latest`，若失败则自动回退至 GitHub Releases API
  Future<AppUpdateInfo> checkUpdate({
    String? baseUrl,
    String? platform,
    String? repo,
  }) async {
    final effectivePlatform = platform ?? currentPlatformKey();
    final effectiveBaseUrl =
        baseUrl ?? (_api.baseUrl.isNotEmpty ? _api.baseUrl : null);

    // 1. 尝试自建聚合服务端接口
    if (effectiveBaseUrl != null && effectiveBaseUrl.trim().isNotEmpty) {
      final cleanUrl = effectiveBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final uri = Uri.parse(
        '$cleanUrl/api/app/latest?platform=$effectivePlatform&version=$currentVersion',
      );
      try {
        final res = await _client.get(
          uri,
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final decoded = json.decode(utf8.decode(res.bodyBytes));
          if (decoded is Map &&
              decoded['code'] == 1 &&
              decoded['data'] is Map) {
            return AppUpdateInfo.fromJson(
              Map<String, dynamic>.from(decoded['data']),
              currentVersion: currentVersion,
              platform: effectivePlatform,
            );
          }
        }
      } catch (_) {
        // 接口不可用或超时，平滑降级至 GitHub
      }
    }

    // 2. 降级备用源：GitHub Releases API
    final targetRepo = repo ?? defaultGitHubRepo;
    final githubUri = Uri.parse(
      'https://api.github.com/repos/$targetRepo/releases/latest',
    );
    try {
      final res = await _client.get(
        githubUri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Bllii-App/$currentVersion',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return AppUpdateInfo.fromGitHubRelease(
            decoded,
            currentVersion: currentVersion,
            platform: effectivePlatform,
          );
        }
      }
    } catch (_) {
      // 两个数据源均失败
    }

    throw const UpdateException('无法获取版本信息，请检查网络连接或稍后重试');
  }

  /// 跳转至下载链接或浏览器打开
  static Future<bool> launchUpdate(String url) async {
    if (url.trim().isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
