// 尺寸目检板:渲染底栏 / 侧边栏(展开+收起) / 详情页 hero 的真实尺寸,
// 用于核对图标大小是否协调。运行:
// flutter test test/ui_size_review_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/models/video_model.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/screens/anime_detail_screen.dart';
import 'package:video_collection_app/theme/app_theme.dart';
import 'package:video_collection_app/widgets/brand_widgets.dart';
import 'package:video_collection_app/widgets/entropy_sidebar.dart';

VideoRecord _fakeVideo() => VideoRecord.fromJson(const {
      'id': 1,
      'name': '葬送的芙莉莲',
      'sub_name': 'enfrente del futuro',
      'hits': 12345,
      'year': '2024',
      'area': '日本',
      'remarks': '更新至第 28 话',
      'language': '日语',
      'content': '勇者一行人旅途结束后的故事。',
      'actor': '种崎敦美(原作),east(作画)',
      'director': '斋藤圭一郎',
      'play_groups': [
        {
          'player_code': 'test',
          'server': '测试线路',
          'episodes': [
            {'name': '第 1 话', 'url': 'https://example.invalid/one.mp4'},
            {'name': '第 2 话', 'url': 'https://example.invalid/two.mp4'},
          ],
        },
      ],
    });

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget host(Widget child, Size size) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: ChangeNotifierProvider(
          create: (_) => AppStateProvider(),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: size.width, height: size.height, child: child),
            ),
          ),
        ),
      );

  testWidgets('size review: bottom nav', (tester) async {
    tester.view.physicalSize = const Size(390, 72);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          bottomNavigationBar: BrandBottomNav(
            currentIndex: index,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/size_bottom_nav.png'),
    );
  });

  testWidgets('size review: sidebar expanded and collapsed', (tester) async {
    tester.view.physicalSize = const Size(340, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: ChangeNotifierProvider(
          create: (_) => AppStateProvider(),
          child: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: sidebarExpandedWidth,
                  child: EntropySidebar(
                    currentIndex: 0,
                    onSelect: (_) {},
                    onSearch: () {},
                    onSettings: () {},
                    onAccount: () {},
                    onWidthChanged: (_) {},
                  ),
                ),
                const VerticalDivider(width: 1),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/size_sidebar_expanded.png'),
    );

    // 收起边栏
    final collapseBtn = find.byTooltip('收起边栏');
    expect(collapseBtn, findsOneWidget);
    await tester.tap(collapseBtn);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/size_sidebar_collapsed.png'),
    );
  });

  testWidgets('size review: detail hero mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      host(
        AnimeDetailContent(
          video: _fakeVideo(),
          related: const [],
          onPlay: (_, _) {},
          onRelated: (_) {},
          onOpenNews: (_) {},
        ),
        const Size(390, 620),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/size_detail_mobile.png'),
    );
  });

  testWidgets('size review: detail hero desktop', (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      host(
        AnimeDetailContent(
          video: _fakeVideo(),
          related: const [],
          onPlay: (_, _) {},
          onRelated: (_) {},
          onOpenNews: (_) {},
        ),
        const Size(1200, 760),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/size_detail_desktop.png'),
    );
  });
}
