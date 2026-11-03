import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows 桌面端：原生标题栏由 windows/runner C++ 的自定义控制条替代。
final bool kIsWindowsDesktop = !kIsWeb && Platform.isWindows;

/// Windows 原生窗口控制条（windows/runner 里用 C++ 实现的右上角
/// 最小化 / 最大化 / 关闭三联按钮）的 Dart 侧桥。
///
/// 非 Windows 平台或通道不存在时静默降级，不影响功能。
class NativeWindow {
  static const MethodChannel _channel = MethodChannel('bllii/native_window');
  static bool _available = true;

  /// 同步原生控制按钮配色与应用明暗主题。
  static void setTheme(bool dark) => _invoke('setTheme', dark);

  /// 全屏播放时隐藏原生控制按钮，退出全屏时恢复。
  static void setControlsVisible(bool visible) =>
      _invoke('setControlsVisible', visible);

  static void _invoke(String method, bool arg) {
    if (!_available) return;
    _channel
        .invokeMethod<void>(method, arg)
        .catchError((_) {
          _available = false;
        });
  }
}
