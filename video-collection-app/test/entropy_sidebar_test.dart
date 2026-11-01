import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/theme/app_theme.dart';
import 'package:video_collection_app/utils/responsive.dart';
import 'package:video_collection_app/widgets/entropy_sidebar.dart';

void main() {
  testWidgets('Desktop sidebar shows profile card and menu groups', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppStateProvider();
    addTearDown(state.dispose);
    await tester.runAsync(() async {
      while (!state.isInitialized) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    var selected = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Row(
              children: [
                EntropySidebar(
                  currentIndex: selected,
                  onSelect: (index) => selected = index,
                  onSettings: () {},
                  onAccount: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的追番'), findsOneWidget);
    expect(find.text('观看历史'), findsOneWidget);
    expect(find.text('账号与积分'), findsOneWidget);
    expect(find.text('番剧分类'), findsOneWidget);
    expect(find.text('热度排行'), findsOneWidget);
    expect(find.text('新番时间表'), findsOneWidget);
    expect(find.text('资讯社区'), findsOneWidget);
    expect(find.text('偏好设置'), findsOneWidget);
    await tester.tap(find.text('资讯社区'));
    expect(selected, 3);
    expect(find.text('登录 / 注册'), findsOneWidget);
    // 品牌行与底部主题按钮已按新版式移除
    expect(find.text('bllii'), findsNothing);
    expect(find.byTooltip('收起边栏'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Content width excludes the desktop sidebar', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopInset(
          sidebarWidth: sidebarExpandedWidth,
          child: Builder(
            builder: (context) =>
                Text('${Responsive.contentWidth(context).round()}'),
          ),
        ),
      ),
    );
    expect(find.text('1024'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
