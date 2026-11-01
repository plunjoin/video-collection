/// 自研路由与页面骨架:[Navigator]/[MaterialPageRoute]/[PopScope]/
/// [Scaffold]。
///
/// 自研路由栈:压栈/出栈/替换,桌面端缩放转场、移动端侧滑转场;
/// Android 返回键由 AppRoot 调 [RouterController.handleSystemBack] 接入。
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' as fw;

import 'container.dart';
import 'gestures.dart';
import 'layout.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// 路由
// ---------------------------------------------------------------------------

/// 页面路由(自研;builder + settings)。
class MaterialPageRoute<T> {
  final fw.WidgetBuilder builder;
  final fw.RouteSettings? settings;

  MaterialPageRoute({required this.builder, this.settings});
}

/// 返回回调签名。
typedef PopInvokedCallback = void Function(bool didPop);

/// 返回拦截(自研;canPop=false 时拦截系统/代码返回)。
class PopScope<T extends Object?> extends fw.StatefulWidget {
  final bool canPop;
  final PopInvokedCallback? onPopInvoked;
  final void Function(bool didPop, T? result)? onPopInvokedWithResult;
  final fw.Widget child;

  const PopScope({
    fw.Key? key,
    this.canPop = true,
    this.onPopInvoked,
    this.onPopInvokedWithResult,
    required this.child,
  }) : super(key: key);

  @override
  fw.State<PopScope<T>> createState() => _PopScopeState<T>();
}

class _PopScopeState<T extends Object?> extends fw.State<PopScope<T>> {
  @override
  fw.Widget build(fw.BuildContext context) {
    final scope = _RouteScope.maybeOf(context);
    scope?.registerPopScope(this);
    return widget.child;
  }
}

/// 单条路由的运行数据。
class _RouteData<T> {
  final MaterialPageRoute<T> route;
  bool closing = false;
  _PopScopeState? popScope;

  _RouteData(this.route);
}

/// 路由控制器(自研;持有路由栈,由 RouterHost 渲染)。
class RouterController extends ChangeNotifier {
  final List<_RouteData> _stack = [];

  bool get canPop => _stack.isNotEmpty;

  int get depth => _stack.length;

  void push<T>(MaterialPageRoute<T> route) {
    _stack.add(_RouteData<T>(route));
    notifyListeners();
  }

  void pushReplacement<T>(MaterialPageRoute<T> route) {
    if (_stack.isNotEmpty) {
      _stack.removeLast();
    }
    _stack.add(_RouteData<T>(route));
    notifyListeners();
  }

  void pop<T>([T? result]) {
    if (_stack.isEmpty) return;
    final top = _stack.last;
    final scope = top.popScope;
    if (scope != null && !scope.widget.canPop) {
      scope.widget.onPopInvoked?.call(false);
      scope.widget.onPopInvokedWithResult?.call(false, null);
      return;
    }
    scope?.widget.onPopInvoked?.call(true);
    scope?.widget.onPopInvokedWithResult?.call(true, result);
    top.closing = true;
    notifyListeners();
    // 退场动画时长后真正移除
    Future.delayed(const Duration(milliseconds: 260), () {
      _stack.remove(top);
      notifyListeners();
    });
  }

  /// 系统返回键(didPopRoute);返回是否已处理。
  bool handleSystemBack() {
    if (_stack.isEmpty) return false;
    pop();
    return true;
  }
}

/// 路由宿主:渲染路由栈(由 AppRoot 挂载)。
class RouterHost extends fw.StatefulWidget {
  final RouterController controller;
  final fw.Widget home;

  const RouterHost({
    fw.Key? key,
    required this.controller,
    required this.home,
  }) : super(key: key);

  @override
  fw.State<RouterHost> createState() => _RouterHostState();
}

class _RouterHostState extends fw.State<RouterHost> {
  RouterController get _effectiveController => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(RouterHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    return Stack(
      children: [
        _RouteScope(
          data: null,
          child: widget.home,
        ),
        for (final data in widget.controller._stack)
          Positioned.fill(
            key: fw.ObjectKey(data),
            child: _RouteTransition(data: data),
          ),
      ],
    );
  }
}

/// 单条路由的转场 + PopScope 注册点。
class _RouteTransition extends fw.StatefulWidget {
  final _RouteData data;

  const _RouteTransition({required this.data});

  @override
  fw.State<_RouteTransition> createState() => _RouteTransitionState();
}

class _RouteTransitionState extends fw.State<_RouteTransition>
    with fw.SingleTickerProviderStateMixin {
  late final fw.AnimationController _controller;

  _RouteData get data => widget.data;

  @override
  void initState() {
    super.initState();
    _controller = fw.AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final platform = defaultTargetPlatform;
    final desktop = platform == fw.TargetPlatform.windows ||
        platform == fw.TargetPlatform.macOS ||
        platform == fw.TargetPlatform.linux;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        var appear = data.closing ? (1 - t) : t;
        if (data.closing) {
          // 退场时控制器继续前进,appear 由 1 → 0
          appear = math.max(0.0, 1 - t);
        }
        final eased = fw.Curves.easeOutCubic.transform(appear.clamp(0.0, 1.0));
        if (desktop) {
          return Opacity(
            opacity: eased,
            child: Transform.scale(
              scale: 0.94 + 0.06 * eased,
              child: child,
            ),
          );
        }
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset((1 - eased) * 80, 0),
            child: child,
          ),
        );
      },
      child: _RouteScope(
        data: data,
        child: fw.Builder(
          builder: (context) => data.route.builder(context),
        ),
      ),
    );
  }
}

/// 路由作用域:给路由内组件提供 PopScope 注册。
class _RouteScope extends fw.InheritedWidget {
  final _RouteData? data;

  const _RouteScope({required this.data, required fw.Widget child})
      : super(child: child);

  static _RouteScope? maybeOf(fw.BuildContext context) {
    return context.getInheritedWidgetOfExactType<_RouteScope>();
  }

  void registerPopScope(_PopScopeState scope) {
    data?.popScope = scope;
  }

  @override
  bool updateShouldNotify(_RouteScope oldWidget) => false;
}

// ---------------------------------------------------------------------------
// Navigator 兼容层
// ---------------------------------------------------------------------------

/// 路由导航入口(自研;Navigator.of(context).push/pop 兼容)。
///
/// 对话框/底部弹层内会先命中 DialogNavigatorScope(见 overlay.dart),
/// pop(result) 走对话框结果桥,而不是弹掉底层路由。
class Navigator {
  static NavigatorState of(fw.BuildContext context) {
    final dialogNav = DialogNavigatorScope.maybeOf(context);
    if (dialogNav != null) {
      return dialogNav.navigatorState;
    }
    final state = context.findAncestorStateOfType<_RouterHostState>();
    assert(state != null, 'RouterHost 未挂载(AppRoot)');
    return NavigatorState._(context, state!._effectiveController);
  }

  /// 静态弹出(兼容 Navigator.pop(context) 用法)。
  static void pop<T>(fw.BuildContext context, [T? result]) {
    of(context).pop(result);
  }

  /// 静态压栈(兼容 Navigator.push 用法)。
  static Future<T?> push<T>(
    fw.BuildContext context,
    MaterialPageRoute<T> route,
  ) {
    return of(context).push(route);
  }
}

/// 导航操作句柄。
class NavigatorState {
  final RouterController? _owner;
  final fw.BuildContext _context;
  final void Function(Object? result)? _dialogClose;

  NavigatorState._(this._context, this._owner, [this._dialogClose]);

  Future<T?> push<T>(MaterialPageRoute<T> route) {
    assert(_owner != null, '对话框导航句柄不支持 push');
    _owner!.push(route);
    return Future<T?>.value();
  }

  Future<T?> pushReplacement<T>(MaterialPageRoute<T> route) {
    assert(_owner != null, '对话框导航句柄不支持 pushReplacement');
    _owner!.pushReplacement(route);
    return Future<T?>.value();
  }

  void pop<T>([T? result]) {
    final owner = _owner;
    if (owner == null) {
      _dialogClose?.call(result);
      return;
    }
    owner.pop(result);
  }

  bool canPop() => _owner?.canPop ?? true;

  void maybePop<T>([T? result]) {
    pop(result);
  }
}

/// 创建对话框/底部弹层专用的导航句柄(pop 走 [onClose] 结果桥)。
NavigatorState createDialogNavigator({
  required fw.BuildContext context,
  required void Function(Object? result) onClose,
}) {
  return NavigatorState._(context, null, onClose);
}

/// 对话框导航作用域(由 overlay.dart 挂载;pop 走对话框结果桥)。
class DialogNavigatorScope extends fw.InheritedWidget {
  final NavigatorState navigatorState;

  const DialogNavigatorScope({
    required this.navigatorState,
    required fw.Widget child,
  }) : super(child: child);

  static DialogNavigatorScope? maybeOf(fw.BuildContext context) {
    return context.getInheritedWidgetOfExactType<DialogNavigatorScope>();
  }

  @override
  bool updateShouldNotify(DialogNavigatorScope oldWidget) => false;
}

// ---------------------------------------------------------------------------
// Scaffold
// ---------------------------------------------------------------------------

/// 页面骨架(替代 material 的 Scaffold)。
class Scaffold extends fw.StatelessWidget {
  final fw.Widget? appBar;
  final fw.Widget? body;
  final Color? backgroundColor;
  final fw.Widget? floatingActionButton;
  final fw.Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;

  const Scaffold({
    fw.Key? key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final insets = fw.MediaQuery.viewInsetsOf(context);
    return Container(
      color: backgroundColor ?? theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          if (appBar != null) appBar!,
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: body ?? const SizedBox.shrink()),
                if (floatingActionButton != null)
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: floatingActionButton!,
                  ),
              ],
            ),
          ),
          if (bottomNavigationBar != null)
            Padding(
              padding: EdgeInsets.only(bottom: insets.bottom),
              child: bottomNavigationBar!,
            ),
        ],
      ),
    );
  }
}
