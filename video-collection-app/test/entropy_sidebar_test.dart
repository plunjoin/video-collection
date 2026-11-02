import 'package:video_collection_app/ui/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/ui/kit.dart';
import 'package:video_collection_app/utils/responsive.dart';
import 'package:video_collection_app/widgets/entropy_sidebar.dart';
import 'test_kit.dart';

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
    expect(findText('我的追番'), findsOneWidget);
    expect(findText('观看历史'), findsOneWidget);
    expect(findText('账号与积分'), findsOneWidget);
    expect(findText('番剧分类'), findsOneWidget);
    expect(findText('热度排行'), findsOneWidget);
    expect(findText('新番时间表'), findsOneWidget);
    expect(findText('资讯社区'), findsOneWidget);
    expect(findText('偏好设置'), findsOneWidget);
    await tester.tap(findText('资讯社区'));
    expect(selected, 3);
    expect(findText('登录 / 注册'), findsOneWidget);
    // 品牌行与底部主题按钮已按新版式移除
    expect(findText('bllii'), findsNothing);
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
    expect(findText('1024'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
