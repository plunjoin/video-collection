import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/theme/app_theme.dart';
import 'package:video_collection_app/utils/responsive.dart';
import 'package:video_collection_app/widgets/entropy_sidebar.dart';

void main() {
  testWidgets('Desktop sidebar follows the collapsible entropy layout', (
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
    var width = sidebarExpandedWidth;
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
                  onSearch: () {},
                  onSettings: () {},
                  onAccount: () {},
                  onWidthChanged: (value) => width = value,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('bllii'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('资讯'), findsOneWidget);
    await tester.tap(find.text('资讯'));
    expect(selected, 3);
    expect(find.text('登录 / 注册'), findsOneWidget);
    expect(find.text('Ctrl+K'), findsOneWidget);
    expect(width, sidebarExpandedWidth);

    await tester.tap(find.byTooltip('收起边栏'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsNothing);
    expect(find.text('登录 / 注册'), findsNothing);
    expect(width, sidebarCollapsedWidth);

    await tester.tap(find.byTooltip('打开边栏'));
    await tester.pumpAndSettle();
    expect(find.text('番剧分类'), findsOneWidget);
    expect(width, sidebarExpandedWidth);
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
