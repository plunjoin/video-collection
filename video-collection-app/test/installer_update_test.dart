import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/models/update_model.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/services/api_service.dart';
import 'package:video_collection_app/services/installer_update_service.dart';
import 'package:video_collection_app/services/update_service.dart';
import 'package:video_collection_app/widgets/update_dialog.dart';

/// 可控的假安装器服务, 用于验证 Provider 的下载/安装状态流转
class _FakeInstallerUpdate extends InstallerUpdateService {
  _FakeInstallerUpdate({this.onDownload, this.onInstall});

  final Future<File> Function(
    String url,
    String version, {
    void Function(double progress)? onProgress,
  })? onDownload;
  final Future<void> Function(String path)? onInstall;

  @override
  Future<File> downloadInstaller(
    String url,
    String version, {
    void Function(double progress)? onProgress,
  }) {
    if (onDownload != null) {
      return onDownload!(url, version, onProgress: onProgress);
    }
    return super.downloadInstaller(url, version, onProgress: onProgress);
  }

  @override
  Future<void> installAndRelaunch(String installerPath) {
    if (onInstall != null) return onInstall!(installerPath);
    return super.installAndRelaunch(installerPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstallerUpdateService.canInstallWithInstaller', () {
    test('windows exe installer is supported', () {
      expect(
        InstallerUpdateService.canInstallWithInstaller(
          'https://example.com/bllii_setup_windows_v1.2.0.exe',
        ),
        isTrue,
      );
      expect(
        InstallerUpdateService.canInstallWithInstaller(
          'HTTPS://EXAMPLE.COM/BLLII_SETUP.EXE',
        ),
        isTrue,
      );
    });

    test('zip / apk / empty links are not supported', () {
      expect(
        InstallerUpdateService.canInstallWithInstaller(
          'https://example.com/bllii_for_windows_v1.2.0.zip',
        ),
        isFalse,
      );
      expect(
        InstallerUpdateService.canInstallWithInstaller(
          'https://example.com/bllii.apk',
        ),
        isFalse,
      );
      expect(InstallerUpdateService.canInstallWithInstaller(''), isFalse);
    });
  });

  group('GitHub Release asset matching', () {
    test('windows setup exe wins over green zip', () {
      final info = AppUpdateInfo.fromGitHubRelease(
        {
          'tag_name': 'v1.2.0',
          'name': 'Release 1.2.0',
          'body': 'changelog',
          'html_url': 'https://github.com/plunjoin/video-collection/releases',
          'assets': [
            {
              'name': 'bllii_for_windows_v1.2.0.zip',
              'browser_download_url':
                  'https://example.com/bllii_for_windows_v1.2.0.zip',
            },
            {
              'name': 'bllii_setup_windows_v1.2.0.exe',
              'browser_download_url':
                  'https://example.com/bllii_setup_windows_v1.2.0.exe',
            },
          ],
        },
        currentVersion: '1.1.0',
        platform: 'windows',
      );
      expect(
        info.downloadUrl,
        'https://example.com/bllii_setup_windows_v1.2.0.exe',
      );
    });

    test('falls back to zip when no setup exe exists', () {
      final info = AppUpdateInfo.fromGitHubRelease(
        {
          'tag_name': 'v1.2.0',
          'name': 'Release 1.2.0',
          'body': 'changelog',
          'html_url': 'https://github.com/plunjoin/video-collection/releases',
          'assets': [
            {
              'name': 'bllii_for_windows_v1.2.0.zip',
              'browser_download_url':
                  'https://example.com/bllii_for_windows_v1.2.0.zip',
            },
          ],
        },
        currentVersion: '1.1.0',
        platform: 'windows',
      );
      expect(info.downloadUrl, contains('bllii_for_windows_v1.2.0.zip'));
    });
  });

  group('InstallerUpdateService.downloadInstaller', () {
    test('streams to temp file and reports progress', () async {
      final payload = List<int>.filled(1024, 65); // 1KB
      final client = MockClient((request) async {
        return http.Response.bytes(payload, 200, headers: {
          'content-length': '${payload.length}',
        });
      });
      final service = InstallerUpdateService(client: client);

      final progresses = <double>[];
      final file = await service.downloadInstaller(
        'https://example.com/bllii_setup_windows_v9.9.9.exe',
        '9.9.9',
        onProgress: progresses.add,
      );

      expect(file.existsSync(), isTrue);
      expect(file.path, endsWith('bllii_update_9.9.9.exe'));
      expect(file.lengthSync(), payload.length);
      expect(progresses, isNotEmpty);
      expect(progresses.last, 1.0);

      file.deleteSync();
    });

    test('throws on non-200 response', () async {
      final client = MockClient((request) async => http.Response('x', 404));
      final service = InstallerUpdateService(client: client);

      expect(
        () => service.downloadInstaller(
          'https://example.com/missing.exe',
          '1.0.0',
        ),
        throwsA(isA<UpdateDownloadException>()),
      );
    });
  });

  group('AppStateProvider installer update flow', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('downloadUpdate stores installer path and installUpdate runs it',
        () async {
      final backendClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 1,
            'data': {
              'version': '1.2.0',
              'title': '发现新版本 v1.2.0',
              'changelog': '修复',
              'download_url':
                  'https://example.com/bllii_setup_windows_v1.2.0.exe',
              'platforms': {
                'windows': 'https://example.com/bllii_setup_windows_v1.2.0.exe',
              },
              'has_update': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      String? installedPath;
      final fake = _FakeInstallerUpdate(
        onDownload: (url, version, {onProgress}) async {
          onProgress?.call(0.5);
          onProgress?.call(1);
          final file = File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}'
            'bllii_update_$version.exe',
          );
          file.writeAsStringSync('fake');
          return file;
        },
        onInstall: (path) async {
          installedPath = path;
        },
      );

      final provider = AppStateProvider(
        api: ApiService.withClient(backendClient),
        updateService: UpdateService(client: backendClient),
        installerUpdate: fake,
      );

      final info = await provider.checkAppUpdate();
      expect(info.hasUpdate, isTrue);
      expect(provider.canUpdateWithInstaller, isTrue);

      await provider.downloadUpdate();
      expect(provider.downloadingUpdate, isFalse);
      expect(provider.downloadedInstallerPath, isNotNull);
      expect(provider.updateDownloadError, isNull);

      await provider.installUpdate();
      expect(installedPath, provider.downloadedInstallerPath);

      // 清理测试产物
      final downloaded = File(provider.downloadedInstallerPath!);
      if (downloaded.existsSync()) downloaded.deleteSync();
    });

    test('downloadUpdate reports error for non-installer links', () async {
      final backendClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 1,
            'data': {
              'version': '1.2.0',
              'title': '发现新版本 v1.2.0',
              'changelog': '修复',
              'download_url': 'https://example.com/bllii.zip',
              'platforms': {'windows': 'https://example.com/bllii.zip'},
              'has_update': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final provider = AppStateProvider(
        api: ApiService.withClient(backendClient),
        updateService: UpdateService(client: backendClient),
        installerUpdate: _FakeInstallerUpdate(),
      );

      await provider.checkAppUpdate();
      expect(provider.canUpdateWithInstaller, isFalse);

      await provider.downloadUpdate();
      expect(provider.downloadedInstallerPath, isNull);
      expect(provider.updateDownloadError, isNotNull);
    });

    testWidgets('UpdateDialog shows download-and-install for exe links',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backendClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 1,
            'data': {
              'version': '1.2.0',
              'title': '发现新版本 v1.2.0',
              'changelog': '修复',
              'download_url': 'https://example.com/bllii_setup_windows_v1.2.0.exe',
              'platforms': {
                'windows': 'https://example.com/bllii_setup_windows_v1.2.0.exe',
              },
              'has_update': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final provider = AppStateProvider(
        api: ApiService.withClient(backendClient),
        updateService: UpdateService(client: backendClient),
        installerUpdate: _FakeInstallerUpdate(),
      );
      final info = await provider.checkAppUpdate();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppStateProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(body: UpdateDialog(info: info)),
          ),
        ),
      );

      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('下载并安装'), findsOneWidget);
      expect(find.text('立即更新'), findsNothing);
      expect(find.text('暂不更新'), findsOneWidget);
    });
  });
}
