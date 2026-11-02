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
  // 返回指定类型的组件本身(与框架 widgetWithText 语义一致),
  // 通过"其子树中存在该文本"来判定。
  return find.byWidgetPredicate(
    (w) => w.runtimeType == widgetType &&
        _containsText(w, text),
  );
}

/// 判断组件(或其子树)是否承载指定文本。
bool _containsText(Widget widget, String text) {
  // 组件自身的文本参数(按钮的 label 等)
  if (widget is Text && widget.data == text) return true;
  if (widget is TextButton && widget.child is Text &&
      (widget.child as Text).data == text) {
    return true;
  }
  var found = false;
  forEachDescendant(widget, (node) {
    if (found) return;
    if (node is Text && node.data == text) {
      found = true;
    }
  });
  return found;
}


/// 按 tooltip 文案查找组件(兼容自研 Tooltip;框架 find.byTooltip 只认
/// material 的 Tooltip 组件)。
Finder findByTooltip(String message) {
  return find.byWidgetPredicate(
    (w) => w is Tooltip && w.message == message,
  );
}


/// 持续滚动直到目标可见(替代 tester.scrollUntilVisible)。
Future<void> scrollUntilVisible(
  WidgetTester tester,
  Finder finder,
  double delta, {
  Finder? scrollable,
  int maxScrolls = 50,
}) async {
  final target = scrollable ?? find.byType(ListView).hitTestable().last;
  for (var i = 0; i < maxScrolls; i++) {
    if (finder.hitTestable().evaluate().isNotEmpty) break;
    await tester.drag(
      target,
      Offset(0, -delta),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }
}

/// 让目标组件在自研滚动容器内可见(替代 tester.ensureVisible;
/// 框架版只认 material 的 Scrollable)。
Future<void> scrollIntoView(
  WidgetTester tester,
  Finder finder, {
  double alignment = 0.0,
}) async {
  if (finder.evaluate().isEmpty) return;
  final context = tester.element(finder.first);
  await Scrollable.ensureVisible(context, alignment: alignment);
  await tester.pumpAndSettle();
  // 自研滚动容器:若目标仍不可见,直接调整滚动容器的偏移
  if (!finder.hitTestable().evaluate().isNotEmpty) {
    final target = context.findRenderObject();
    if (target is RenderBox && target.hasSize) {
      final global = target.localToGlobal(Offset.zero);
      final rect = global & target.size;
      // 选视口面积最小的滚动容器(最贴近目标);
      // 宽度为 0 的容器(未布局)跳过
      final candidates = mountedScrollables.where((state) {
        final viewport = state.context.findRenderObject();
        return viewport is RenderBox &&
            viewport.hasSize &&
            viewport.size.width > 0 &&
            viewport.size.height > 0;
      }).toList()
        ..sort((a, b) {
          final av = a.context.findRenderObject() as RenderBox;
          final bv = b.context.findRenderObject() as RenderBox;
          return (av.size.width * av.size.height)
              .compareTo(bv.size.width * bv.size.height);
        });
      for (final state in candidates) {
        final viewport = state.context.findRenderObject() as RenderBox;
        final viewRect = viewport.localToGlobal(Offset.zero) & viewport.size;
        var offset = state.scrollOffset;
        if (rect.top < viewRect.top) {
          offset += rect.top - viewRect.top;
        } else if (rect.bottom > viewRect.bottom) {
          offset += rect.bottom - viewRect.bottom;
        } else {
          continue;
        }
        state.applyScroll(offset, dragging: false);
        await tester.pumpAndSettle();
        if (finder.hitTestable().evaluate().isNotEmpty) break;
      }
    }
  }
}
