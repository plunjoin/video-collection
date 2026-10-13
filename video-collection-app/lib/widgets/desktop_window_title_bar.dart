import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// 桌面端沉浸式自定义标题栏 (可拖拽窗口 + 自定义标题 + 快速主题切换 + 精致窗口三联按钮)
class DesktopWindowTitleBar extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final bool isDark;
  final double height;
  final List<Widget>? actions;
  final bool showThemeToggle;

  const DesktopWindowTitleBar({
    super.key,
    this.leading,
    this.title,
    required this.isDark,
    this.height = 40,
    this.actions,
    this.showThemeToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Responsive.isDesktopPlatform) {
      return const SizedBox.shrink();
    }

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D31) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkBorder.withValues(alpha: 0.5)
                : AppColors.lightBorder,
            width: 0.8,
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                child: title ?? _buildDefaultTitle(context, isDark),
              ),
            ),
          ),

          // 右侧自定义操作按钮
          ...?actions,

          // 快速主题明暗切换开关
          if (showThemeToggle && MediaQuery.sizeOf(context).width >= 480) ...[
            _ThemeQuickToggle(isDark: isDark),
            const SizedBox(width: 4),
          ],

          // 右侧精致窗口三联系统控制按钮
          DesktopWindowControls(isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildDefaultTitle(BuildContext context, bool isDark) {
    final width = MediaQuery.sizeOf(context).width;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: AppColors.purple.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(
            Icons.play_circle_filled_rounded,
            size: 13,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
              children: [
                const TextSpan(
                  text: 'bllii',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                TextSpan(
                  text: ' · More Stories, Together',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (width >= 480) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.primary600.withValues(alpha: 0.15)
                  : AppColors.primary50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDark
                    ? AppColors.primary600.withValues(alpha: 0.25)
                    : AppColors.primary200,
                width: 0.6,
              ),
            ),
            child: const Text(
              'Desktop',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TitleBarNavButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;

  const _TitleBarNavButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_TitleBarNavButton> createState() => _TitleBarNavButtonState();
}

class _TitleBarNavButtonState extends State<_TitleBarNavButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: widget.isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeQuickToggle extends StatefulWidget {
  final bool isDark;
  const _ThemeQuickToggle({required this.isDark});

  @override
  State<_ThemeQuickToggle> createState() => _ThemeQuickToggleState();
}

class _ThemeQuickToggleState extends State<_ThemeQuickToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.isDark ? '切换为明亮模式' : '切换为暗夜模式',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: () {
            final appState = Provider.of<AppStateProvider>(
              context,
              listen: false,
            );
            appState.setThemeMode(
              widget.isDark ? ThemeMode.light : ThemeMode.dark,
            );
          },
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.primary500.withValues(alpha: 0.08))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.isDark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              size: 15,
              color: widget.isDark
                  ? AppColors.gold
                  : AppColors.purple,
            ),
          ),
        ),
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

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowHoverButton(
            icon: Icons.remove_rounded,
            tooltip: '最小化',
            onTap: () => windowManager.minimize(),
            iconColor: iconColor,
          ),
          const SizedBox(width: 2),
          _WindowHoverButton(
            icon: _isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: _isMaximized ? 11 : 13,
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
          const SizedBox(width: 2),
          _WindowHoverButton(
            icon: Icons.close_rounded,
            tooltip: '关闭',
            onTap: () => windowManager.close(),
            isClose: true,
            iconColor: iconColor,
          ),
        ],
      ),
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
    this.iconSize = 14,
    this.isClose = false,
  });

  @override
  State<_WindowHoverButton> createState() => _WindowHoverButtonState();
}

class _WindowHoverButtonState extends State<_WindowHoverButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Gradient? gradient;
    Color iconColor = widget.iconColor;
    List<BoxShadow>? shadows;

    if (_isHovered) {
      if (widget.isClose) {
        gradient = const LinearGradient(
          colors: [Color(0xFFF43F5E), Color(0xFFE11D48)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
        iconColor = Colors.white;
        shadows = [
          BoxShadow(
            color: const Color(0xFFF43F5E).withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ];
      } else {
        bg = Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.08)
            : AppColors.primary500.withValues(alpha: 0.08);
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              gradient: gradient,
              borderRadius: BorderRadius.circular(6),
              boxShadow: shadows,
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
