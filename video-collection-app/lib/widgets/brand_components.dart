import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// 具有 bllii 品牌流光边框、平滑上浮动效与柔和阴影的现代悬浮卡片
class BrandHoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final double elevation;
  final Color? backgroundColor;

  const BrandHoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.borderRadius,
    this.elevation = 0,
    this.backgroundColor,
  });

  @override
  State<BrandHoverCard> createState() => _BrandHoverCardState();
}

class _BrandHoverCardState extends State<BrandHoverCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = widget.borderRadius ?? BorderRadius.circular(16);
    final isDesktop = !kIsWeb && Responsive.isDesktopPlatform;

    final defaultBg = widget.backgroundColor ??
        (isDark ? AppColors.darkCard : Colors.white);

    return MouseRegion(
      onEnter: (_) => isDesktop ? setState(() => _isHovered = true) : null,
      onExit: (_) => isDesktop ? setState(() => _isHovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _isHovered ? -3.5 : 0, 0),
        decoration: BoxDecoration(
          color: defaultBg,
          borderRadius: radius,
          border: Border.all(
            color: _isHovered
                ? AppColors.purple.withValues(alpha: isDark ? 0.6 : 0.45)
                : (isDark
                    ? AppColors.darkBorder.withValues(alpha: 0.6)
                    : AppColors.lightBorder),
            width: _isHovered ? 1.2 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? AppColors.purple.withValues(alpha: isDark ? 0.22 : 0.12)
                  : Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
              blurRadius: _isHovered ? 16 : 6,
              offset: Offset(0, _isHovered ? 6 : 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: radius,
              splashColor: AppColors.purple.withValues(alpha: 0.1),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 具有轻量弹性触感缩放 (Spring Scale) 与品牌流光的微动效按钮
class BrandScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final bool outlined;

  const BrandScaleButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.gradient,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    this.borderRadius,
    this.outlined = false,
  });

  @override
  State<BrandScaleButton> createState() => _BrandScaleButtonState();
}

class _BrandScaleButtonState extends State<BrandScaleButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onPressed != null;
    final radius = widget.borderRadius ?? BorderRadius.circular(24);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => enabled ? setState(() => _isPressed = true) : null,
        onTapUp: (_) => enabled ? setState(() => _isPressed = false) : null,
        onTapCancel: () => enabled ? setState(() => _isPressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: widget.padding,
            decoration: BoxDecoration(
              gradient: widget.outlined
                  ? null
                  : (enabled
                      ? (widget.gradient ?? AppColors.brandGradient)
                      : null),
              color: widget.outlined
                  ? (_isHovered
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : AppColors.primary50)
                      : Colors.transparent)
                  : (!enabled
                      ? (isDark ? AppColors.darkBorder : AppColors.lightBorder)
                      : widget.color),
              borderRadius: radius,
              border: widget.outlined
                  ? Border.all(
                      color: _isHovered
                          ? AppColors.primary500
                          : (isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder),
                      width: 1,
                    )
                  : null,
              boxShadow: enabled && !widget.outlined
                  ? [
                      BoxShadow(
                        color: AppColors.purple.withValues(
                          alpha: _isHovered ? 0.35 : 0.18,
                        ),
                        blurRadius: _isHovered ? 12 : 6,
                        offset: Offset(0, _isHovered ? 4 : 2),
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 桌面端与应用通用的高质感搜索胶囊 (带悬浮微光与快捷键提示)
class BrandSearchPill extends StatefulWidget {
  final VoidCallback onTap;
  final String hintText;
  final String? shortcutLabel;
  final double height;

  const BrandSearchPill({
    super.key,
    required this.onTap,
    this.hintText = '搜索精彩番剧、动态与资讯...',
    this.shortcutLabel = 'Ctrl + K',
    this.height = 36,
  });

  @override
  State<BrandSearchPill> createState() => _BrandSearchPillState();
}

class _BrandSearchPillState extends State<BrandSearchPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isDark
                ? (_isHovered ? const Color(0xFF1E2A44) : const Color(0xFF162137))
                : (_isHovered ? Colors.white : const Color(0xFFF1F4FD)),
            borderRadius: BorderRadius.circular(widget.height / 2),
            border: Border.all(
              color: _isHovered
                  ? AppColors.purple.withValues(alpha: 0.6)
                  : (isDark
                      ? AppColors.darkBorder.withValues(alpha: 0.6)
                      : AppColors.lightBorder),
              width: _isHovered ? 1.2 : 0.8,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppColors.purple.withValues(alpha: isDark ? 0.2 : 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 16,
                color: _isHovered
                    ? AppColors.purple
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.hintText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
              if (widget.shortcutLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    widget.shortcutLabel!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 具有半透明磨砂亚克力质感的沉浸式容器
class BrandGlassPanel extends StatelessWidget {
  final Widget child;
  final double blur;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? tintColor;

  const BrandGlassPanel({
    super.key,
    required this.child,
    this.blur = 16,
    this.borderRadius,
    this.padding = const EdgeInsets.all(16),
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(16);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tintColor ??
                (isDark
                    ? const Color(0xFF1E293B).withValues(alpha: 0.75)
                    : Colors.white.withValues(alpha: 0.82)),
            borderRadius: radius,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.6),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 品牌流光角标与状态标签
class BrandBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final bool isGradient;

  const BrandBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.isGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primary500;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        gradient: isGradient ? AppColors.brandGradient : null,
        color: isGradient ? null : effectiveColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: isGradient
            ? null
            : Border.all(
                color: effectiveColor.withValues(alpha: 0.3),
                width: 0.6,
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 11,
              color: isGradient ? Colors.white : effectiveColor,
            ),
            const SizedBox(width: 3.5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isGradient ? Colors.white : effectiveColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
