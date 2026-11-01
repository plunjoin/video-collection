/// 自研浮层体系:浮层宿主 + [Overlay]/[OverlayEntry] + [showDialog]/
/// [AlertDialog]/[showModalBottomSheet]/[SnackBar]/[ScaffoldMessenger]。
///
/// AppRoot 挂载唯一 [OverlayHost],所有对话框/底部弹层/浮窗都压入其栈。
import 'dart:math' as math;
import 'dart:async' show Completer, Timer;
import 'dart:ui' show Brightness;
import 'package:flutter/rendering.dart';

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' as fw;

import 'buttons.dart';
import 'container.dart';
import 'text.dart';
import 'gestures.dart';
import 'layout.dart';
import 'scroll.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// 浮层宿主
// ---------------------------------------------------------------------------

/// 浮层条目(自研;由宿主栈管理)。
class OverlayEntry {
  final fw.WidgetBuilder builder;
  final bool opaque;

  OverlayHostEntryState? _host;
  bool _mounted = true;

  OverlayEntry({required this.builder, this.opaque = false});

  void markNeedsBuild() {
    _host?.refresh();
  }

  void remove() {
    if (_mounted) {
      _mounted = false;
      _host?.removeEntry(this);
    }
  }
}

/// 浮层条目的宿主句柄基类。
class OverlayHostEntryState {
  void refresh() {}
  void removeEntry(OverlayEntry entry) {}
}

/// 应用级浮层宿主:所有 dialog / bottom sheet / overlay 的承载者。
class OverlayHost extends fw.StatefulWidget {
  final fw.Widget child;

  const OverlayHost({fw.Key? key, required this.child}) : super(key: key);

  static OverlayHostState of(fw.BuildContext context) {
    final state = context.findAncestorStateOfType<OverlayHostState>();
    assert(state != null, 'OverlayHost 未挂载');
    return state!;
  }

  @override
  fw.State<OverlayHost> createState() => OverlayHostState();
}

class _HostEntry {
  final OverlayEntry entry;
  fw.Widget? cached;

  _HostEntry(this.entry);
}

class OverlayHostState extends fw.State<OverlayHost> {
  final List<_HostEntry> _entries = [];

  bool get hasEntries => _entries.isNotEmpty;

  void insertEntry(OverlayEntry entry) {
    setState(() {
      final host = _HostEntry(entry);
      entry._host = _HostProxy(this, host);
      _entries.add(host);
    });
  }

  void insertBefore(OverlayEntry entry, OverlayEntry anchor) {
    setState(() {
      final host = _HostEntry(entry);
      entry._host = _HostProxy(this, host);
      final anchorIndex =
          _entries.indexWhere((e) => e.entry == anchor);
      if (anchorIndex >= 0) {
        _entries.insert(anchorIndex, host);
      } else {
        _entries.add(host);
      }
    });
  }

  void removeEntry(OverlayEntry entry) {
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((e) => e.entry == entry);
    });
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    return Stack(
      children: [
        widget.child,
        for (final host in _entries)
          Positioned.fill(
            child: _EntryWrapper(
              key: fw.ObjectKey(host),
              host: host,
            ),
          ),
      ],
    );
  }
}

/// OverlayEntry 的宿主句柄(供 markNeedsBuild/remove 使用)。
class _HostProxy extends OverlayHostEntryState {
  final OverlayHostState owner;
  final _HostEntry host;

  _HostProxy(this.owner, this.host);

  @override
  void refresh() {
    owner.setState(() {
      host.cached = null;
    });
  }
}

class _EntryWrapper extends fw.StatefulWidget {
  final _HostEntry host;

  const _EntryWrapper({super.key, required this.host});

  @override
  fw.State<_EntryWrapper> createState() => _EntryWrapperState();
}

class _EntryWrapperState extends fw.State<_EntryWrapper> {
  @override
  fw.Widget build(fw.BuildContext context) {
    return widget.host.entry.builder(context);
  }
}

// ---------------------------------------------------------------------------
// Overlay 兼容层(player 等使用的 Overlay.of / OverlayEntry)
// ---------------------------------------------------------------------------

/// 浮层入口(自研;兼容 Overlay.of(context) / OverlayEntry 用法)。
class Overlay {
  final OverlayHostState _host;

  Overlay._(this._host);

  static Overlay of(fw.BuildContext context, {bool rootOverlay = false}) {
    return Overlay._(OverlayHost.of(context));
  }

  /// 插入浮层。
  OverlayEntryState insert(OverlayEntry entry) {
    _host.insertEntry(entry);
    return OverlayEntryState._(entry, _host);
  }
}

/// 已插入浮层的句柄。
class OverlayEntryState {
  final OverlayEntry _entry;
  final OverlayHostState _host;

  OverlayEntryState._(this._entry, this._host);

  void remove() {
    _host.removeEntry(_entry);
  }
}

// ---------------------------------------------------------------------------
// 对话框
// ---------------------------------------------------------------------------

/// 弹出对话框,返回结果经 Navigator.pop 传递。
Future<T?> showDialog<T>({
  required fw.BuildContext context,
  required fw.WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  fw.RouteSettings? routeSettings,
}) {
  final host = OverlayHost.of(context);
  final completer = Completer<T?>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      return DialogScrim(
        barrierColor: barrierColor ?? const Color(0x66000000),
        barrierDismissible: barrierDismissible,
        onDismiss: () {
          if (!completer.isCompleted) {
            completer.complete(null);
            entry.remove();
          }
        },
        child: DialogPopBridge<T>(
          onPopped: (result) {
            if (!completer.isCompleted) {
              completer.complete(result);
              entry.remove();
            }
          },
          child: builder(ctx),
        ),
      );
    },
  );
  host.insertEntry(entry);
  return completer.future;
}

/// 对话框遮罩:半透明背景 + 居中内容 + 点击关闭。
class DialogScrim extends fw.StatelessWidget {
  final Color barrierColor;
  final bool barrierDismissible;
  final VoidCallback onDismiss;
  final fw.Widget child;

  const DialogScrim({
    fw.Key? key,
    required this.barrierColor,
    required this.barrierDismissible,
    required this.onDismiss,
    required this.child,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: barrierDismissible ? onDismiss : null,
      child: Container(
        color: barrierColor,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: child,
        ),
      ),
    );
  }
}

/// 监听内容内 Navigator.pop(result) 的桥(对话框关闭走这里)。
class DialogPopBridge<T> extends fw.StatefulWidget {
  final fw.ValueChanged<T?> onPopped;
  final fw.Widget child;

  const DialogPopBridge({
    fw.Key? key,
    required this.onPopped,
    required this.child,
  }) : super(key: key);

  @override
  fw.State<DialogPopBridge<T>> createState() => _DialogPopBridgeState<T>();
}

class _DialogPopBridgeState<T> extends fw.State<DialogPopBridge<T>> {
  @override
  fw.Widget build(fw.BuildContext context) {
    return DialogResultScope<T>(
      onResult: widget.onPopped,
      child: widget.child,
    );
  }
}

/// 对话框结果作用域:Navigator.pop 在对话框树内时改走这里。
class DialogResultScope<T> extends fw.InheritedWidget {
  final fw.ValueChanged<T?> onResult;

  const DialogResultScope({
    fw.Key? key,
    required this.onResult,
    required fw.Widget child,
  }) : super(key: key, child: child);

  static DialogResultScope<T>? maybeOf<T>(fw.BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<DialogResultScope<T>>();
    return scope;
  }

  @override
  bool updateShouldNotify(DialogResultScope<T> oldWidget) => false;
}

/// 标准对话框(替代 material 的 AlertDialog)。
class AlertDialog extends fw.StatelessWidget {
  final fw.Widget? title;
  final fw.Widget? content;
  final List<fw.Widget>? actions;
  final Color? backgroundColor;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? titlePadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;
  final bool scrollable;
  final double? actionsMaxWidth;

  const AlertDialog({
    fw.Key? key,
    this.title,
    this.content,
    this.actions,
    this.backgroundColor,
    this.shape,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
    this.scrollable = false,
    this.actionsMaxWidth,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final shapeRadius = BorderRadius.circular(24);
    return Container(
      width: math.min(420, double.infinity),
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
      decoration: BoxDecoration(
        color: backgroundColor ??
            (dark ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: shapeRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: titlePadding ??
                  const EdgeInsets.fromLTRB(24, 22, 24, 0),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: theme.fontFamily,
                  fontFamilyFallback: theme.fontFamilyFallback,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: dark ? const Color(0xFFF9FAFF) : const Color(0xFF353B58),
                ),
                child: title!,
              ),
            ),
          if (content != null)
            Flexible(
              child: SingleChildScrollView(
                padding: contentPadding ??
                    const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontFamily: theme.fontFamily,
                    fontFamilyFallback: theme.fontFamilyFallback,
                    fontSize: 13,
                    height: 1.6,
                    color: dark
                        ? const Color(0xFFB9C2D8)
                        : const Color(0xFF55607E),
                  ),
                  child: content!,
                ),
              ),
            ),
          if (actions != null && actions!.isNotEmpty)
            Padding(
              padding: actionsPadding ??
                  const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions!.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    actions![i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部弹层。
Future<T?> showModalBottomSheet<T>({
  required fw.BuildContext context,
  required fw.WidgetBuilder builder,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  bool barrierDismissible = true,
  bool isScrollControlled = false,
  bool useSafeArea = true,
  Color? barrierColor,
}) {
  final host = OverlayHost.of(context);
  final completer = Completer<T?>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      return _BottomSheetScaffold<T>(
        backgroundColor: backgroundColor,
        barrierColor: barrierColor ?? const Color(0x59000000),
        barrierDismissible: barrierDismissible,
        onClose: (result) {
          if (!completer.isCompleted) {
            completer.complete(result);
            entry.remove();
          }
        },
        child: builder(ctx),
      );
    },
  );
  host.insertEntry(entry);
  return completer.future;
}

class _BottomSheetScaffold<T> extends fw.StatefulWidget {
  final Color? backgroundColor;
  final Color barrierColor;
  final bool barrierDismissible;
  final fw.ValueChanged<T?> onClose;
  final fw.Widget child;

  const _BottomSheetScaffold({
    required this.backgroundColor,
    required this.barrierColor,
    required this.barrierDismissible,
    required this.onClose,
    required this.child,
  });

  @override
  fw.State<_BottomSheetScaffold<T>> createState() =>
      _BottomSheetScaffoldState<T>();
}

class _BottomSheetScaffoldState<T>
    extends fw.State<_BottomSheetScaffold<T>> {
  double _dragOffset = 0;
  Offset? _pointerStart;

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.barrierDismissible ? () => widget.onClose(null) : null,
      child: Container(
        color: widget.barrierColor,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Listener(
            onPointerDown: (e) => _pointerStart = e.position,
            onPointerMove: (e) {
              if (_pointerStart != null) {
                final dy = e.position.dy - _pointerStart!.dy;
                setState(() => _dragOffset = math.max(0, dy * 0.6));
              }
            },
            onPointerUp: (e) {
              final drag = _dragOffset;
              _pointerStart = null;
              if (drag > 80) {
                widget.onClose(null);
              } else {
                setState(() => _dragOffset = 0);
              }
            },
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: DialogResultScope<T>(
                onResult: widget.onClose,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.backgroundColor ??
                        (dark ? const Color(0xFF1E293B) : Colors.white),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x29000000),
                        blurRadius: 24,
                        offset: Offset(0, -6),
                      ),
                    ],
                  ),
                  child: fw.Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 4),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Flexible(child: widget.child),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SnackBar
// ---------------------------------------------------------------------------

/// 轻提示(替代 material 的 SnackBar)。
class SnackBar {
  final fw.Widget content;
  final Duration duration;
  final SnackBarBehavior? behavior;
  final Color? backgroundColor;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? elevation;
  final EdgeInsetsGeometry? padding;
  final bool showCloseIcon;
  final Color? closeIconColor;
  final fw.Widget? action;

  const SnackBar({
    fw.Key? key,
    required this.content,
    this.duration = const Duration(seconds: 4),
    this.behavior,
    this.backgroundColor,
    this.shape,
    this.margin,
    this.width,
    this.elevation,
    this.padding,
    this.showCloseIcon = false,
    this.closeIconColor,
    this.action,
  });
}

/// 浮动/固定行为。
enum SnackBarBehavior { fixed, floating }

/// SnackBar 管理器(自研;ScaffoldMessenger.of(context).showSnackBar 兼容)。
class ScaffoldMessenger extends fw.InheritedWidget {
  final ScaffoldMessengerState state;

  const ScaffoldMessenger({
    fw.Key? key,
    required this.state,
    required fw.Widget child,
  }) : super(key: key, child: child);

  static ScaffoldMessengerState of(fw.BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<ScaffoldMessenger>();
    assert(scope != null, 'ScaffoldMessenger 未挂载');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(ScaffoldMessenger oldWidget) => false;
}

class ScaffoldMessengerState extends fw.State<fw.StatefulWidget> {
  final List<SnackBar> _queue = [];
  SnackBar? _current;
  Timer? _hideTimer;
  bool _visible = false;

  void showSnackBar(SnackBar snackBar) {
    _queue.add(snackBar);
    if (!_visible) {
      _showNext();
    }
  }

  void hideCurrentSnackBar() {
    _dismissCurrent();
  }

  void clearSnackBars() {
    _dismissCurrent();
    _queue.clear();
  }

  void _showNext() {
    if (_queue.isEmpty || !mounted) return;
    setState(() {
      _current = _queue.removeAt(0);
      _visible = true;
    });
    _hideTimer?.cancel();
    _hideTimer = Timer(_current!.duration, _dismissCurrent);
  }

  void _dismissCurrent() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _visible = false;
      _current = null;
    });
    Timer(const Duration(milliseconds: 200), _showNext);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_visible && _current != null)
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _SnackBarView(snackBar: _current!),
            ),
          ),
      ],
    );
  }
}

class _SnackBarView extends fw.StatelessWidget {
  final SnackBar snackBar;

  const _SnackBarView({required this.snackBar});

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: snackBar.width,
      margin: snackBar.margin ??
          const EdgeInsets.symmetric(horizontal: 8),
      padding: snackBar.padding ??
          const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: snackBar.backgroundColor ??
            (dark ? const Color(0xFF1E293B) : const Color(0xFF555F83)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: theme.fontFamily,
                fontFamilyFallback: theme.fontFamilyFallback,
                fontSize: 12,
                color: Colors.white,
                height: 1.5,
              ),
              child: snackBar.content,
            ),
          ),
          if (snackBar.action != null) ...[
            const SizedBox(width: 12),
            snackBar.action!,
          ],
        ],
      ),
    );
  }
}
