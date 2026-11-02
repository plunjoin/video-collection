/// 测试辅助:为自研组件库提供旧版测试 API 的等价替身。
///
/// - [AppTheme]:原 M3 主题工厂的门面(映射到 buildAppTheme)。
/// - [MaterialApp]:AppRoot 的测试包装(不依赖任何 Flutter 自带组件)。
/// - [DefaultTabController]:自研 TabController 的继承作用域。
import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/ui/kit.dart';

/// 主题工厂门面。
class AppTheme {
  static ThemeData get lightTheme =>
      buildAppTheme(Brightness.light, const Color(0xFF597BEA));
  static ThemeData get darkTheme =>
      buildAppTheme(Brightness.dark, const Color(0xFF597BEA));
  static ThemeData themed(Brightness brightness, Color accent) =>
      buildAppTheme(brightness, accent);
}

/// 测试用应用包装(替代 material 的 MaterialApp)。
class MaterialApp extends StatelessWidget {
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final Widget? home;
  final Widget Function(BuildContext, Widget?)? builder;
  final bool debugShowCheckedModeBanner;

  const MaterialApp({
    Key? key,
    this.theme,
    this.darkTheme,
    this.home,
    this.builder,
    this.debugShowCheckedModeBanner = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppRoot(
      theme: theme ?? AppTheme.lightTheme,
      darkTheme: darkTheme ?? AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: home ?? const SizedBox.shrink(),
      builder: builder,
    );
  }
}

/// 自研 TabController 继承作用域(替代 material 的 DefaultTabController)。
class DefaultTabController extends StatefulWidget {
  final int length;
  final Widget child;

  const DefaultTabController({
    Key? key,
    required this.length,
    required this.child,
  }) : super(key: key);

  static TabController of(BuildContext context) {
    final state = context.findAncestorStateOfType<_DefaultTabControllerState>();
    assert(state != null, 'DefaultTabController 未挂载');
    return state!.controller;
  }

  @override
  State<DefaultTabController> createState() => _DefaultTabControllerState();
}

class _DefaultTabControllerState extends State<DefaultTabController>
    with SingleTickerProviderStateMixin {
  late final TabController controller =
      TabController(length: widget.length, vsync: this);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}


/// 自研 [Text] 的文本查找器(替代 find.text)。
Finder findText(String text, {bool skipOffstage = true}) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && widget.data == text,
    skipOffstage: skipOffstage,
  );
}

/// 自研 [Text] 的包含文本查找器。
Finder findTextContaining(String text, {bool skipOffstage = true}) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && (widget.data ?? '').contains(text),
    skipOffstage: skipOffstage,
  );
}


/// 兼容框架 find.widgetWithText:按"包含指定文本的子组件"查找。
///
/// 框架实现依赖 material Text 的内部结构,自研 Text 结构不同,
/// 这里改为:先按类型找到候选,再在其子树中查找文本匹配。
Finder findWidgetWithText(Type widgetType, String text) {
  return find.descendant(
    of: find.byType(widgetType),
    matching: find.byWidgetPredicate(
      (w) => w is Text && w.data == text,
    ),
  );
}
