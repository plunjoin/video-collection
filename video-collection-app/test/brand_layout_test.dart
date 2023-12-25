import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/main.dart';
import 'package:video_collection_app/models/video_model.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/theme/app_theme.dart';
import 'package:video_collection_app/widgets/brand_widgets.dart';
import 'package:video_collection_app/widgets/episode_selector.dart';
import 'package:video_collection_app/widgets/hero_banner.dart';
import 'package:video_collection_app/widgets/search_bar_widget.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('Brand navigation and search fit a $width px screen', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    const BrandLogo(width: 104),
                    const SizedBox(width: 12),
                    Expanded(child: SearchBarWidget(onTap: () {})),
                  ],
                ),
              ),
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    HeroBannerWidget(
                      banners: const [],
                      onPlayTap: (_) {},
                      onDetailTap: (_) {},
                    ),
                    BrandStoryBanner(onTap: () {}),
                  ],
                ),
              ),
              bottomNavigationBar: BrandBottomNav(
                currentIndex: selected,
                onSelected: (index) => setState(() => selected = index),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('发现'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(selected, 4);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Episode selection preserves the route and episode indexes', (
    tester,
  ) async {
    (int, int)? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EpisodeSelectorWidget(
            playGroups: [
              PlayGroup(
                playerCode: 'test',
                server: '测试线路',
                note: '',
                episodes: [
                  Episode(
                    name: '第 1 话',
                    url: 'https://example.invalid/one.mp4',
                  ),
                  Episode(
                    name: '第 2 话',
                    url: 'https://example.invalid/two.mp4',
                  ),
                ],
              ),
            ],
            currentGroupIndex: 0,
            currentEpisodeIndex: 0,
            onSelected: (group, episode) => selected = (group, episode),
          ),
        ),
      ),
    );
    await tester.tap(find.text('第 2 话'));
    expect(selected, (0, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Default theme is light and the existing dark preference is retained',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fresh = AppStateProvider();
      await tester.runAsync(() async {
        while (!fresh.isInitialized) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(fresh.themeMode, ThemeMode.light);
      fresh.dispose();
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final saved = AppStateProvider();
      await tester.runAsync(() async {
        while (!saved.isInitialized) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(saved.themeMode, ThemeMode.dark);
      saved.dispose();
    },
  );

  testWidgets('Mobile app opens profile with the new layout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppStateProvider(),
        child: const BlliiApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('我的').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('热爱故事的你'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
