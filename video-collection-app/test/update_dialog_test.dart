import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/models/update_model.dart';
import 'package:video_collection_app/widgets/update_dialog.dart';

void main() {
  testWidgets('UpdateDialog displays latest version status when no update',
      (tester) async {
    final info = AppUpdateInfo.upToDate(currentVersion: '1.0.0');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateDialog(info: info),
        ),
      ),
    );

    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.textContaining('已经是最新版本'), findsOneWidget);
    expect(find.text('好的'), findsOneWidget);
    expect(find.text('立即更新'), findsNothing);
  });

  testWidgets('UpdateDialog displays update prompt when new version available',
      (tester) async {
    const info = AppUpdateInfo(
      version: '1.2.0',
      title: '发现新版本 v1.2.0',
      changelog: '1. 新增检查更新功能\n2. 优化视频清晰度',
      forceUpdate: false,
      downloadUrl: 'https://example.com/bllii.apk',
      hasUpdate: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UpdateDialog(info: info),
        ),
      ),
    );

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v1.2.0'), findsNWidgets(2)); // in header and version comparison
    expect(find.textContaining('新增检查更新功能'), findsOneWidget);
    expect(find.text('暂不更新'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('UpdateDialog enforces non-dismissible state when forceUpdate is true',
      (tester) async {
    const info = AppUpdateInfo(
      version: '2.0.0',
      title: '重大版本更新',
      changelog: '安全紧急升级',
      forceUpdate: true,
      downloadUrl: 'https://example.com/bllii.apk',
      hasUpdate: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UpdateDialog(info: info),
        ),
      ),
    );

    expect(find.text('必须更新'), findsOneWidget);
    expect(find.text('暂不更新'), findsNothing);
    expect(find.text('立即更新'), findsOneWidget);
  });
}
