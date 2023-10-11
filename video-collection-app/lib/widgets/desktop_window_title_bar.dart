import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// 桌面端沉浸式自定义标题栏 (可拖拽窗口 + 自定义标题 + 窗口三联按钮)
class DesktopWindowTitleBar extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final bool isDark;

  const DesktopWindowTitleBar({
    super.key,
    this.leading,
    this.title,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Responsive.isDesktopPlatform) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 左侧标志/前置
          ?leading,

          // 中间区域：全域可拖拽移动窗口 + 双击最大化/还原
          Expanded(
            child: DragToMoveArea(
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                child:
                    title ??
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary600, Color(0xFF6366F1)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.play_circle_filled_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'bllii · More Stories, Together',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primary600.withValues(alpha: 0.15)
                                : AppColors.primary50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Desktop',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary500,
                            ),
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),

          // 右侧窗口三联系统控制按钮
          DesktopWindowControls(isDark: isDark),
        ],
      ),
    );
  }
}

/// 桌面端窗口三联控制按钮 (最小化、最大化/还原、关闭)
class DesktopWindowControls extends StatefulWidget {
  final bool isDark;

  const DesktopWindowControls({super.key, required this.isDark});

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Responsive.isDesktopPlatform) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Responsive.isDesktopPlatform) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {
        _isMaximized = maximized;
      });
    }
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Responsive.isDesktopPlatform) {
      return const SizedBox.shrink();
    }

    final iconColor = widget.isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowHoverButton(
          icon: Icons.remove_rounded,
          tooltip: '最小化',
          onTap: () => windowManager.minimize(),
          iconColor: iconColor,
        ),
        _WindowHoverButton(
          icon: _isMaximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          iconSize: _isMaximized ? 12 : 14,
          tooltip: _isMaximized ? '还原' : '最大化',
          onTap: () async {
            if (_isMaximized) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          iconColor: iconColor,
        ),
        _WindowHoverButton(
          icon: Icons.close_rounded,
          tooltip: '关闭',
          onTap: () => windowManager.close(),
          isClose: true,
          iconColor: iconColor,
        ),
      ],
    );
  }
}

class _WindowHoverButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color iconColor;
  final double iconSize;
  final bool isClose;

  const _WindowHoverButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.iconColor,
    this.iconSize = 15,
    this.isClose = false,
  });

  @override
  State<_WindowHoverButton> createState() => _WindowHoverButtonState();
}

class _WindowHoverButtonState extends State<_WindowHoverButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.transparent;
    Color iconColor = widget.iconColor;

    if (_isHovered) {
      if (widget.isClose) {
        bg = const Color(0xFFE81123); // Windows 原生关闭红
        iconColor = Colors.white;
      } else {
        bg = Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.06);
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 44,
            height: 38,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
