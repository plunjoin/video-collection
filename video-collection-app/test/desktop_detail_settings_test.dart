import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/models/video_model.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/screens/anime_detail_screen.dart';
import 'package:video_collection_app/screens/settings_screen.dart';
import 'package:video_collection_app/services/fullscreen_service.dart';
import 'package:video_collection_app/theme/app_theme.dart';
import 'package:video_collection_app/widgets/brand_intro.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), (call) async => false);
  });
  for (final width in [320.0, 390.0, 960.0, 1440.0]) {
    testWidgets('Detail layout fits $width and episode selection remains functional', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final video = VideoRecord.fromJson({'id': 42, 'name': '这是一个用于检查 Windows 与手机布局的长番剧标题',
        'content': '剧情简介。' * 60, 'remarks': '更新至第 12 话', 'actor': '演员甲 / 演员乙',
        'play_groups': [{'player_code': 'test', 'episodes': [{'name': '第 1 话', 'url': 'one'}, {'name': '第 2 话', 'url': 'two'}]}]});
      (int, int)? selected;
      await tester.pumpWidget(ChangeNotifierProvider(create: (_) => AppStateProvider(), child: MaterialApp(
        theme: AppTheme.lightTheme, home: Scaffold(body: AnimeDetailContent(video: video, related: [video],
          onPlay: (group, episode) => selected = (group, episode), onRelated: (_) {})))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('desktop-detail-columns')), width >= 840 ? findsOneWidget : findsNothing);
      await tester.ensureVisible(find.text('第 2 话'));
      await tester.tap(find.text('第 2 话'));
      expect(selected, (0, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('Standalone settings changes and persists mode and accent', (tester) async {
    final state = AppStateProvider();
    addTearDown(state.dispose);
    await tester.runAsync(() async {
      while (!state.isInitialized) { await Future<void>.delayed(Duration.zero); }
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(
      theme: AppTheme.lightTheme, home: const SettingsScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('樱花粉'));
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(state.accent, 'pink');
    expect(state.themeMode, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('accent'), 'pink');
    expect(prefs.getString('theme_mode'), 'dark');
    expect(find.text('服务端地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Intro rect reflects actual progress and supports reduced motion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MediaQuery(data: MediaQueryData(disableAnimations: true),
      child: Center(child: BrandIntro(progress: .35)))));
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .35);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('Desktop fullscreen enters OS fullscreen and restores original state', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), (call) async { calls.add(call); return false; });
    final fullscreen = FullscreenService();
    await fullscreen.setEnabled(true);
    await fullscreen.setEnabled(false);
    expect(calls.map((c) => c.method), ['isFullScreen', 'setFullScreen', 'setFullScreen']);
    expect(calls[1].arguments, {'isFullScreen': true});
    expect(calls[2].arguments, {'isFullScreen': false});
  });
}
