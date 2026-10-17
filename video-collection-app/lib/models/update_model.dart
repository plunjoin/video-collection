import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 获取当前运行平台对应的标识键名
String currentPlatformKey() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isIOS) return 'ios';
  return 'unknown';
}

/// 语义化版本号比对
/// 若 v1 > v2 返回 1；若 v1 < v2 返回 -1；若相等返回 0
int compareVersions(String v1, String v2) {
  final clean1 = v1.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final clean2 = v2.trim().replaceFirst(RegExp(r'^[vV]'), '');

  final parts1 = clean1.split('+');
  final parts2 = clean2.split('+');

  final verNums1 = parts1[0]
      .split(RegExp(r'[\.\-]'))
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  final verNums2 = parts2[0]
      .split(RegExp(r'[\.\-]'))
      .map((e) => int.tryParse(e) ?? 0)
      .toList();

  final maxLen = verNums1.length > verNums2.length
      ? verNums1.length
      : verNums2.length;
  for (int i = 0; i < maxLen; i++) {
    final num1 = i < verNums1.length ? verNums1[i] : 0;
    final num2 = i < verNums2.length ? verNums2[i] : 0;
    if (num1 > num2) return 1;
    if (num1 < num2) return -1;
  }

  if (parts1.length > 1 && parts2.length > 1) {
    final b1 = int.tryParse(parts1[1]) ?? 0;
    final b2 = int.tryParse(parts2[1]) ?? 0;
    if (b1 > b2) return 1;
    if (b1 < b2) return -1;
  }

  return 0;
}

/// 客户端更新信息模型
class AppUpdateInfo {
  final String version;
  final int versionCode;
  final String title;
  final String changelog;
  final bool forceUpdate;
  final String downloadUrl;
  final String releaseUrl;
  final String? publishTime;
  final Map<String, String> platforms;
  final bool hasUpdate;

  const AppUpdateInfo({
    required this.version,
    this.versionCode = 1,
    required this.title,
    required this.changelog,
    this.forceUpdate = false,
    required this.downloadUrl,
    this.releaseUrl = '',
    this.publishTime,
    this.platforms = const {},
    required this.hasUpdate,
  });

  factory AppUpdateInfo.upToDate({required String currentVersion}) {
    return AppUpdateInfo(
      version: currentVersion,
      title: '已是最新版本',
      changelog: '当前版本已是最新，无需更新。',
      forceUpdate: false,
      downloadUrl: '',
      hasUpdate: false,
    );
  }

  factory AppUpdateInfo.fromJson(
    Map<String, dynamic> json, {
    String? currentVersion,
    String? platform,
  }) {
    final rawVer = json['version']?.toString() ??
        json['latest_version']?.toString() ??
        '1.0.0';
    final ver = rawVer.replaceFirst(RegExp(r'^[vV]'), '');
    final cleanCurrent = currentVersion?.replaceFirst(RegExp(r'^[vV]'), '');

    final bool computedHasUpdate = cleanCurrent != null
        ? compareVersions(ver, cleanCurrent) > 0
        : (json['has_update'] == true);

    final platformsRaw = json['platforms'];
    final Map<String, String> platforms = {};
    if (platformsRaw is Map) {
      platformsRaw.forEach((k, v) {
        if (v is String) platforms[k.toString()] = v;
        if (v is Map && v['download_url'] != null) {
          platforms[k.toString()] = v['download_url'].toString();
        }
      });
    }

    final pKey = platform ?? currentPlatformKey();
    String downloadUrl = json['download_url']?.toString() ?? '';
    if (platforms.containsKey(pKey) && platforms[pKey]!.isNotEmpty) {
      downloadUrl = platforms[pKey]!;
    }

    return AppUpdateInfo(
      version: ver,
      versionCode: json['version_code'] is int
          ? json['version_code'] as int
          : int.tryParse('${json['version_code']}') ?? 1,
      title: json['title']?.toString() ?? '发现新版本 v$ver',
      changelog: json['changelog']?.toString() ?? '修复已知问题，优化使用体验',
      forceUpdate: json['force_update'] == true ||
          json['force_update'] == '1' ||
          json['force_update'] == 'true',
      downloadUrl: downloadUrl,
      releaseUrl: json['release_url']?.toString() ??
          json['html_url']?.toString() ??
          '',
      publishTime: json['publish_time']?.toString() ??
          json['published_at']?.toString(),
      platforms: platforms,
      hasUpdate: json['has_update'] is bool
          ? json['has_update'] as bool
          : computedHasUpdate,
    );
  }

  factory AppUpdateInfo.fromGitHubRelease(
    Map<String, dynamic> json, {
    required String currentVersion,
    String? platform,
  }) {
    final tagName = json['tag_name']?.toString() ?? '1.0.0';
    final ver = tagName.replaceFirst(RegExp(r'^[vV]'), '');
    final body = json['body']?.toString() ?? '';
    final htmlUrl = json['html_url']?.toString() ??
        'https://github.com/plunjoin/video-collection/releases/latest';
    final assets = json['assets'] is List ? json['assets'] as List : const [];
    final Map<String, String> platforms = {};

    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name']?.toString().toLowerCase() ?? '';
      final browserDownloadUrl =
          asset['browser_download_url']?.toString() ?? '';
      if (browserDownloadUrl.isEmpty) continue;

      if (name.endsWith('.apk') || name.contains('android')) {
        platforms['android'] = browserDownloadUrl;
      } else if (name.endsWith('.zip') &&
          (name.contains('win') || name.contains('windows'))) {
        platforms['windows'] = browserDownloadUrl;
      } else if (name.endsWith('.tar.gz') || name.contains('linux')) {
        platforms['linux'] = browserDownloadUrl;
      } else if (name.endsWith('.zip') &&
          (name.contains('mac') || name.contains('darwin'))) {
        platforms['macos'] = browserDownloadUrl;
      } else if (name.endsWith('.ipa') || name.contains('ios')) {
        platforms['ios'] = browserDownloadUrl;
      }
    }

    final pKey = platform ?? currentPlatformKey();
    String matchedDownloadUrl = htmlUrl;
    if (platforms.containsKey(pKey) && platforms[pKey]!.isNotEmpty) {
      matchedDownloadUrl = platforms[pKey]!;
    } else if (assets.isNotEmpty &&
        assets.first is Map &&
        assets.first['browser_download_url'] != null) {
      matchedDownloadUrl = assets.first['browser_download_url'].toString();
    }

    final cleanCurrent = currentVersion.replaceFirst(RegExp(r'^[vV]'), '');
    final hasUpdate = compareVersions(ver, cleanCurrent) > 0;

    return AppUpdateInfo(
      version: ver,
      versionCode: 1,
      title: json['name']?.toString() ?? '发现新版本 v$ver',
      changelog: body.trim().isEmpty ? '常规性能优化与已知问题修复' : body,
      forceUpdate: false,
      downloadUrl: matchedDownloadUrl,
      releaseUrl: htmlUrl,
      publishTime: json['published_at']?.toString(),
      platforms: platforms,
      hasUpdate: hasUpdate,
    );
  }
}
