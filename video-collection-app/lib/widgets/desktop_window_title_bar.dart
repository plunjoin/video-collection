import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../theme/brand_icons.dart';

/// 桌面端沉浸式自定义标题栏 (可拖拽窗口 + 快速主题切换 + 精致窗口三联按钮)。
/// 左上角不再放品牌内容：品牌行交给侧栏，避免 titlebar 与 sidebar 视觉重叠。
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
    this.height = 36,
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
                child: title ?? const SizedBox.shrink(),
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

}

class _TitleBarNavButton extends StatefulWidget {
  final BrandIconData icon;
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
            child: BrandIcon(
              widget.icon,
              size: 13,
              monochrome: true,
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
            child: BrandIcon(
              widget.isDark
                  ? BIcons.sun
                  : BIcons.moon,
              monochrome: true,
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
            icon: BIcons.minus,
            tooltip: '最小化',
            onTap: () => windowManager.minimize(),
            iconColor: iconColor,
          ),
          const SizedBox(width: 2),
          _WindowHoverButton(
            icon: _isMaximized
                ? BIcons.restore
                : BIcons.square,
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
            icon: BIcons.close,
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
  final BrandIconData icon;
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
            child: BrandIcon(widget.icon, size: widget.iconSize, color: iconColor, monochrome: true),
          ),
        ),
      ),
    );
  }
}
