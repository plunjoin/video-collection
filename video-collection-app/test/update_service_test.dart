import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_collection_app/models/update_model.dart';
import 'package:video_collection_app/services/update_service.dart';

void main() {
  group('Version Comparison Tests', () {
    test('standard semver comparisons', () {
      expect(compareVersions('1.0.1', '1.0.0'), 1);
      expect(compareVersions('1.0.0', '1.0.1'), -1);
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.10.0', '1.9.0'), 1);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
      expect(compareVersions('0.9.5', '1.0.0'), -1);
    });

    test('v prefix handling', () {
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
      expect(compareVersions('v1.2.1', '1.2.0'), 1);
      expect(compareVersions('1.2.0', 'v1.2.1'), -1);
      expect(compareVersions('V2.0.0', 'v1.9.9'), 1);
    });

    test('build number and unequal length comparisons', () {
      expect(compareVersions('1.0.0+2', '1.0.0+1'), 1);
      expect(compareVersions('1.0.0+1', '1.0.0+2'), -1);
      expect(compareVersions('1.0.0+1', '1.0.0+1'), 0);
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1.0.0', '1.0'), 0);
    });
  });

  group('AppUpdateInfo Model Tests', () {
    test('fromJson parses server response correctly', () {
      final json = {
        'version': '1.2.0',
        'version_code': 2,
        'title': '发现新版本 v1.2.0',
        'changelog': '1. 修复播放器全屏问题\n2. 优化弹幕加载速度',
        'force_update': false,
        'download_url': 'https://example.com/app.apk',
        'publish_time': '2026-10-17 00:00:00',
        'platforms': {
          'android': 'https://example.com/bllii.apk',
          'windows': 'https://example.com/bllii.zip',
        },
        'has_update': true,
      };

      final infoAndroid = AppUpdateInfo.fromJson(
        json,
        currentVersion: '1.0.0',
        platform: 'android',
      );
      expect(infoAndroid.version, '1.2.0');
      expect(infoAndroid.hasUpdate, isTrue);
      expect(infoAndroid.downloadUrl, 'https://example.com/bllii.apk');
      expect(infoAndroid.forceUpdate, isFalse);
      expect(infoAndroid.changelog, contains('修复播放器全屏问题'));

      final infoWindows = AppUpdateInfo.fromJson(
        json,
        currentVersion: '1.0.0',
        platform: 'windows',
      );
      expect(infoWindows.downloadUrl, 'https://example.com/bllii.zip');
    });

    test('fromGitHubRelease parses GitHub API asset links correctly', () {
      final gitHubJson = {
        'tag_name': 'v1.1.0',
        'name': 'Bllii Release v1.1.0',
        'body': '• 增加检查更新功能\n• 提升弹幕响应速度',
        'html_url': 'https://github.com/plunjoin/video-collection/releases/tag/v1.1.0',
        'published_at': '2026-10-17T02:00:00Z',
        'assets': [
          {
            'name': 'bllii_for_android_v1.1.0.apk',
            'browser_download_url':
                'https://github.com/plunjoin/video-collection/releases/download/v1.1.0/bllii_for_android_v1.1.0.apk',
          },
          {
            'name': 'bllii_for_windows_v1.1.0.zip',
            'browser_download_url':
                'https://github.com/plunjoin/video-collection/releases/download/v1.1.0/bllii_for_windows_v1.1.0.zip',
          },
        ],
      };

      final androidInfo = AppUpdateInfo.fromGitHubRelease(
        gitHubJson,
        currentVersion: '1.0.0',
        platform: 'android',
      );
      expect(androidInfo.version, '1.1.0');
      expect(androidInfo.hasUpdate, isTrue);
      expect(androidInfo.downloadUrl, contains('bllii_for_android_v1.1.0.apk'));

      final winInfo = AppUpdateInfo.fromGitHubRelease(
        gitHubJson,
        currentVersion: '1.0.0',
        platform: 'windows',
      );
      expect(winInfo.downloadUrl, contains('bllii_for_windows_v1.1.0.zip'));

      final upToDateInfo = AppUpdateInfo.fromGitHubRelease(
        gitHubJson,
        currentVersion: '1.2.0',
        platform: 'android',
      );
      expect(upToDateInfo.hasUpdate, isFalse);
    });
  });

  group('UpdateService Tests', () {
    test('checkUpdate succeeds from backend server', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/app/latest') {
          return http.Response(
            jsonEncode({
              'code': 1,
              'data': {
                'version': '1.3.0',
                'title': '发现新版本 v1.3.0',
                'changelog': '全新更新',
                'force_update': false,
                'download_url': 'https://example.com/bllii_v1.3.0.apk',
                'platforms': {'android': 'https://example.com/bllii_v1.3.0.apk'},
                'has_update': true,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = UpdateService(client: client);
      final update = await service.checkUpdate(
        baseUrl: 'https://api.example.com',
        platform: 'android',
      );

      expect(update.version, '1.3.0');
      expect(update.hasUpdate, isTrue);
      expect(update.downloadUrl, 'https://example.com/bllii_v1.3.0.apk');
    });

    test('checkUpdate falls back to GitHub Releases when backend fails', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.4.0',
              'name': 'Release 1.4.0',
              'body': 'GitHub release log',
              'html_url': 'https://github.com/plunjoin/video-collection/releases/latest',
              'assets': [
                {
                  'name': 'bllii_for_android_v1.4.0.apk',
                  'browser_download_url':
                      'https://github.com/plunjoin/video-collection/releases/download/v1.4.0/bllii_for_android_v1.4.0.apk',
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // Backend returns 502
        return http.Response('Bad Gateway', 502);
      });

      final service = UpdateService(client: client);
      final update = await service.checkUpdate(
        baseUrl: 'https://broken-backend.example.com',
        platform: 'android',
      );

      expect(update.version, '1.4.0');
      expect(update.hasUpdate, isTrue);
      expect(update.changelog, 'GitHub release log');
      expect(update.downloadUrl, contains('bllii_for_android_v1.4.0.apk'));
    });

    test('checkUpdate throws UpdateException when both backend and GitHub fail', () async {
      final client = MockClient((request) async {
        return http.Response('Error', 500);
      });

      final service = UpdateService(client: client);
      expect(
        () => service.checkUpdate(
          baseUrl: 'https://broken.example.com',
          platform: 'android',
        ),
        throwsA(isA<UpdateException>()),
      );
    });
  });
}
