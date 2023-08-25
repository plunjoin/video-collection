import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_collection_app/providers/app_state_provider.dart';
import 'package:video_collection_app/screens/profile_screen.dart';
import 'package:video_collection_app/theme/app_theme.dart';
import 'package:video_collection_app/widgets/brand_controls.dart';

void main() {
  void narrowScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Custom tabs stay in sync with taps and swipes', (tester) async {
    narrowScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              final controller = DefaultTabController.of(context);
              return Scaffold(
                appBar: BrandAppBar(
                  title: const Text('排行榜'),
                  bottom: BrandTabs(
                    controller: controller,
                    tabs: const [Text('人气热播'), Text('最新作品')],
                  ),
                ),
                body: TabBarView(
                  controller: controller,
                  children: const [
                    Center(child: Text('人气内容')),
                    Center(child: Text('最新内容')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('最新作品'));
    await tester.pumpAndSettle();
    expect(find.text('最新内容').hitTestable(), findsOneWidget);
    final controller = tester
        .widget<BrandTabs>(find.byType(BrandTabs))
        .controller;
    expect(controller.index, 1);
    await tester.drag(find.byType(TabBarView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(controller.index, 0);
    expect(find.text('人气内容').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pills toggle selection and disabled pills cannot be pressed', (
    tester,
  ) async {
    bool selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                BrandPill(
                  label: const Text('动画'),
                  selected: selected,
                  onSelected: (value) => setState(() => selected = value),
                ),
                const BrandPill(label: Text('暂不可用')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('动画'));
    await tester.pump();
    expect(selected, isTrue);
    await tester.tap(find.text('动画'));
    await tester.pump();
    expect(selected, isFalse);
    final disabled = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '暂不可用'),
    );
    expect(disabled.onPressed, isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'Options return values and cancel on a narrow ${dark ? 'dark' : 'light'} screen',
      (tester) async {
        narrowScreen(tester);
        String? result = 'initial';
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('排序'),
                  onPressed: () async {
                    result = await showBrandOptions<String>(
                      context,
                      title: '选择排列方式',
                      options: [('new', '最近更新'), ('popular', '人气优先')],
                      selected: 'new',
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('排序'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('人气优先'));
        await tester.pumpAndSettle();
        expect(result, 'popular');
        expect(find.byType(BrandDialog), findsNothing);
        await tester.tap(find.text('排序'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Profile settings fit with the keyboard and dismiss cleanly', (
    tester,
  ) async {
    narrowScreen(tester);
    SharedPreferences.setMockInitialValues({});
    final state = AppStateProvider();
    await tester.runAsync(() async {
      while (!state.isInitialized) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), (call) async => false);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('热爱故事的你'), findsOneWidget);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观模式'), findsOneWidget);
    expect(find.text('主题颜色'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
