import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/responsive.dart';

/// Owns the native window transition, so leaving playback restores the window.
class FullscreenService {
  bool _active = false;
  bool _wasFullscreen = false;
  Future<void> setEnabled(bool enabled) async {
    if (_active == enabled) return;
    if (Responsive.isDesktopPlatform) {
      if (enabled) {
        _wasFullscreen = await windowManager.isFullScreen();
        await windowManager.setFullScreen(true);
      } else {
        await windowManager.setFullScreen(_wasFullscreen);
      }
    } else if (Responsive.isMobilePlatform) {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      await SystemChrome.setPreferredOrientations(
        enabled
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : DeviceOrientation.values,
      );
    }
    _active = enabled;
  }
}
