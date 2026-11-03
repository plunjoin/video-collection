import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/shared/ui/kit.dart';

/// 主题工厂门面。
class AppTheme {
  static ThemeData get lightTheme =>
      buildAppTheme(Brightness.light, AppColors.brandSolid);
  static ThemeData get darkTheme =>
      buildAppTheme(Brightness.dark, AppColors.brandSolid);
  static ThemeData themed(Brightness brightness, Color accent) =>
      buildAppTheme(brightness, accent);
}

/// 文本查找器。
Finder findText(String text, {bool skipOffstage = true}) {
  return find.text(text, skipOffstage: skipOffstage);
}

/// 包含文本查找器。
Finder findTextContaining(String text, {bool skipOffstage = true}) {
  return find.textContaining(text, skipOffstage: skipOffstage);
}

/// 按 tooltip 文案查找组件。
Finder findByTooltip(String message) {
  return find.byTooltip(message);
}

/// 兼容 find.widgetWithText。
Finder findWidgetWithText(Type widgetType, String text) {
  return find.widgetWithText(widgetType, text);
}

/// 持续滚动直到目标可见。
Future<void> scrollUntilVisible(
  WidgetTester tester,
  Finder finder,
  double delta, {
  Finder? scrollable,
  int maxScrolls = 50,
}) async {
  Finder target;
  if (scrollable != null) {
    final candidate = find.descendant(
      of: scrollable,
      matching: find.byType(Scrollable),
    );
    target = candidate.evaluate().isNotEmpty ? candidate.first : scrollable;
  } else {
    target = find.byType(Scrollable).hitTestable().last;
  }
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: target,
    maxScrolls: maxScrolls,
  );
}

/// 让目标组件可见。
Future<void> scrollIntoView(
  WidgetTester tester,
  Finder finder,
) async {
  if (finder.evaluate().isEmpty) return;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
