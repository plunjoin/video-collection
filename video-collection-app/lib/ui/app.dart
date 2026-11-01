/// 自研应用根:[AppRoot]——替代 MaterialApp。
///
/// 职责:明暗主题解析与继承、默认文本样式、方向性(LTR)、设备度量
/// (MediaQuery 管道)、焦点作用域、浮层宿主、轻提示宿主、路由宿主。
import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' as fw;

import 'nav.dart';
import 'overlay.dart';
import 'text.dart';
import 'theme.dart';

/// 应用根组件(自研;MaterialApp 的替代品)。
class AppRoot extends fw.StatefulWidget {
  final String title;
  final ThemeData theme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;
  final fw.Widget home;
  final bool debugShowCheckedModeBanner;
  final fw.Widget Function(fw.BuildContext, fw.Widget?)? builder;

  const AppRoot({
    fw.Key? key,
    this.title = '',
    required this.theme,
    required this.darkTheme,
    required this.themeMode,
    required this.home,
    this.debugShowCheckedModeBanner = false,
    this.builder,
  }) : super(key: key);

  @override
  fw.State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends fw.State<AppRoot>
    with fw.WidgetsBindingObserver {
  Brightness _platformBrightness = Brightness.light;
  final RouterController _router = RouterController();
  final fw.FocusScopeNode _focusScopeNode = fw.FocusScopeNode();

  @override
  void initState() {
    super.initState();
    fw.WidgetsBinding.instance.addObserver(this);
    _platformBrightness =
        fw.WidgetsBinding.instance.platformDispatcher.platformBrightness;
    fw.WidgetsBinding.instance.platformDispatcher
        .onPlatformBrightnessChanged = _handleBrightnessChanged;
  }

  @override
  void dispose() {
    fw.WidgetsBinding.instance.platformDispatcher
        .onPlatformBrightnessChanged = null;
    fw.WidgetsBinding.instance.removeObserver(this);
    _focusScopeNode.dispose();
    _router.dispose();
    super.dispose();
  }

  void _handleBrightnessChanged() {
    if (!mounted) return;
    setState(() {
      _platformBrightness =
          fw.WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
  }

  @override
  Future<bool> didPopRoute() async {
    // Android 返回键:优先交给路由栈
    if (_router.handleSystemBack()) {
      return true;
    }
    return super.didPopRoute();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final dark = widget.themeMode == ThemeMode.dark ||
        (widget.themeMode == ThemeMode.system &&
            _platformBrightness == Brightness.dark);
    final data = dark ? widget.darkTheme : widget.theme;

    fw.Widget content = OverlayHost(
      child: ScaffoldMessengerHost(
        child: RouterHost(
          controller: _router,
          home: widget.home,
        ),
      ),
    );
    if (widget.builder != null) {
      content = widget.builder!(context, content);
    }

    return fw.Directionality(
      textDirection: fw.TextDirection.ltr,
      child: fw.FocusScope(
        node: _focusScopeNode,
        child: fw.MediaQuery.fromView(
          view: fw.View.of(context),
          child: Theme(
            data: data,
            child: DefaultTextStyle(
              style: data.textTheme.bodyMedium ??
                  const TextStyle(fontSize: 13),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
