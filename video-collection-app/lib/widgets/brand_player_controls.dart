import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brand_components.dart';
import '../theme/brand_icons.dart';

/// 具有 bllii 品牌渐变色与缓冲指示的高精度进度条轨道
class BrandGradientSliderTrackShape extends RoundedRectSliderTrackShape {
  final Gradient gradient;
  final double bufferProgress; // 0.0 ~ 1.0
  final double additionalActiveTrackHeight;

  const BrandGradientSliderTrackShape({
    this.gradient = AppColors.brandGradient,
    this.bufferProgress = 0.0,
    this.additionalActiveTrackHeight = 1.0,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 1.0,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Canvas canvas = context.canvas;

    // 1. 底层背景轨道 (未播放部分)
    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ??
          Colors.white.withValues(alpha: 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(trackRect.height / 2)),
      inactivePaint,
    );

    // 2. 缓冲进度轨道 (已缓存部分)
    if (bufferProgress > 0.0) {
      final double bufferWidth =
          (trackRect.width * bufferProgress.clamp(0.0, 1.0));
      if (bufferWidth > 0) {
        final Rect bufferRect = Rect.fromLTWH(
          trackRect.left,
          trackRect.top,
          bufferWidth,
          trackRect.height,
        );
        final Paint bufferPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.32);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            bufferRect,
            Radius.circular(trackRect.height / 2),
          ),
          bufferPaint,
        );
      }
    }

    // 3. 激活进度轨道 (已播放部分，呈现品牌渐变色)
    final double activeWidth =
        (thumbCenter.dx - trackRect.left).clamp(0.0, trackRect.width);
    if (activeWidth > 0) {
      final double activeHeight =
          trackRect.height + this.additionalActiveTrackHeight;
      final Rect activeRect = Rect.fromLTWH(
        trackRect.left,
        trackRect.top - (this.additionalActiveTrackHeight / 2),
        activeWidth,
        activeHeight,
      );
      final Paint activePaint = Paint()
        ..shader = gradient.createShader(activeRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          activeRect,
          Radius.circular(activeHeight / 2),
        ),
        activePaint,
      );
    }
  }
}

/// 具有品牌外发光环与白瓷内核的高质感滑块游标
class BrandSliderThumbShape extends SliderComponentShape {
  final double radius;
  final Color glowColor;
  final Color ringColor;

  const BrandSliderThumbShape({
    this.radius = 6.5,
    this.glowColor = AppColors.purple,
    this.ringColor = AppColors.primary400,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius + 4);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final double scale = 1.0 + (activationAnimation.value * 0.25);
    final double currentRadius = radius * scale;

    // 外发光层
    final Paint glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(center, currentRadius + 3.5, glowPaint);

    // 品牌色外环
    final Paint ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, currentRadius, ringPaint);

    // 纯白高光内芯
    final Paint innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, currentRadius - 2.5, innerPaint);
  }
}

/// 磨砂亚克力微交互按钮，专为播放器控制栏定制
class BrandPlayerButton extends StatefulWidget {
  final BrandIconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final Color? iconColor;
  final Gradient? gradient;
  final Color? backgroundColor;
  final BoxBorder? border;
  final bool glow;
  final Color? glowColor;

  const BrandPlayerButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 38,
    this.iconSize = 20,
    this.tooltip,
    this.iconColor,
    this.gradient,
    this.backgroundColor,
    this.border,
    this.glow = false,
    this.glowColor,
  });

  @override
  State<BrandPlayerButton> createState() => _BrandPlayerButtonState();
}

class _BrandPlayerButtonState extends State<BrandPlayerButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final effectiveGlowColor = widget.glowColor ?? AppColors.purple;

    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => enabled ? setState(() => _isHovered = true) : null,
      onExit: (_) => enabled ? setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTapDown: (_) => enabled ? setState(() => _isPressed = true) : null,
        onTapUp: (_) => enabled ? setState(() => _isPressed = false) : null,
        onTapCancel: () => enabled ? setState(() => _isPressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.92 : (_isHovered ? 1.08 : 1.0),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: widget.gradient,
              color: widget.gradient != null
                  ? null
                  : (widget.backgroundColor ??
                      Colors.white.withValues(
                        alpha: _isHovered ? 0.22 : 0.12,
                      )),
              border: widget.border ??
                  Border.all(
                    color: Colors.white.withValues(
                      alpha: _isHovered ? 0.35 : 0.16,
                    ),
                    width: 0.8,
                  ),
              boxShadow: widget.glow && enabled
                  ? [
                      BoxShadow(
                        color: effectiveGlowColor.withValues(
                          alpha: _isHovered ? 0.55 : 0.35,
                        ),
                        blurRadius: _isHovered ? 18 : 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: BrandIcon(
                widget.icon,
                size: widget.iconSize,
                color: widget.iconColor ??
                    (enabled ? Colors.white : Colors.white38),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.32,
      duration: const Duration(milliseconds: 150),
      child: button,
    );
  }
}

/// 播放器专属选项微胶囊 (支持流光渐变激活、线路选择、弹幕开关、倍速等)
class BrandPlayerPill extends StatefulWidget {
  final Widget? leading;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? activeColor;
  final bool isGradient;
  final String? tooltip;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const BrandPlayerPill({
    super.key,
    this.leading,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.activeColor,
    this.isGradient = false,
    this.tooltip,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  @override
  State<BrandPlayerPill> createState() => _BrandPlayerPillState();
}

class _BrandPlayerPillState extends State<BrandPlayerPill> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final effectiveActiveColor = widget.activeColor ?? AppColors.primary500;

    Widget pill = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => enabled ? setState(() => _isHovered = true) : null,
      onExit: (_) => enabled ? setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTapDown: (_) => enabled ? setState(() => _isPressed = true) : null,
        onTapUp: (_) => enabled ? setState(() => _isPressed = false) : null,
        onTapCancel: () => enabled ? setState(() => _isPressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.94 : (_isHovered ? 1.04 : 1.0),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: widget.active && widget.isGradient
                  ? AppColors.brandGradient
                  : null,
              color: (widget.active && widget.isGradient)
                  ? null
                  : (widget.active
                      ? effectiveActiveColor.withValues(alpha: 0.22)
                      : Colors.white.withValues(
                          alpha: _isHovered ? 0.20 : 0.12,
                        )),
              border: Border.all(
                color: widget.active
                    ? (widget.isGradient
                        ? Colors.transparent
                        : effectiveActiveColor.withValues(alpha: 0.65))
                    : Colors.white.withValues(
                        alpha: _isHovered ? 0.35 : 0.16,
                      ),
                width: 0.8,
              ),
              boxShadow: widget.active
                  ? [
                      BoxShadow(
                        color: (widget.isGradient
                                ? AppColors.purple
                                : effectiveActiveColor)
                            .withValues(alpha: _isHovered ? 0.40 : 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight:
                        widget.active ? FontWeight.w700 : FontWeight.w500,
                    color: widget.active
                        ? Colors.white
                        : (_isHovered ? Colors.white : Colors.white70),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      pill = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: pill,
      );
    }

    return pill;
  }
}

/// 播放器居中主控。只保留一颗悬浮播放键，上一集 / 下一集在鼠标悬停时才浮现，
/// 避免大块磨砂胶囊挡住画面。
class BrandPlayerCenterDeck extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final VoidCallback? onPlayPrev;
  final VoidCallback? onPlayNext;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final bool isCompact;

  const BrandPlayerCenterDeck({
    super.key,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onPlayPrev,
    required this.onPlayNext,
    required this.onSeekBackward,
    required this.onSeekForward,
    this.isCompact = false,
  });

  @override
  State<BrandPlayerCenterDeck> createState() => _BrandPlayerCenterDeckState();
}

class _BrandPlayerCenterDeckState extends State<BrandPlayerCenterDeck> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact = widget.isCompact;
    final mainSize = compact ? 44.0 : 52.0;
    final mainIconSize = compact ? 24.0 : 28.0;
    final sideSize = compact ? 30.0 : 34.0;
    final sideIconSize = compact ? 15.0 : 17.0;
    final gap = compact ? 8.0 : 12.0;

    Widget side({required BrandIconData icon, required VoidCallback? onTap,
        required String tip}) {
      return IgnorePointer(
        ignoring: !_hovered || onTap == null,
        child: AnimatedOpacity(
          opacity: _hovered && onTap != null ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: BrandPlayerButton(
            icon: icon,
            onPressed: onTap,
            size: sideSize,
            iconSize: sideIconSize,
            tooltip: tip,
            backgroundColor: Colors.black.withValues(alpha: 0.38),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          side(
            icon: BIcons.prev,
            onTap: widget.onPlayPrev,
            tip: '上一集',
          ),
          SizedBox(width: gap),
          BrandPlayerButton(
            icon: widget.isPlaying
                ? BIcons.pause
                : BIcons.play,
            onPressed: widget.onTogglePlay,
            size: mainSize,
            iconSize: mainIconSize,
            gradient: AppColors.brandGradient,
            glow: true,
            glowColor: AppColors.purple,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 0.8,
            ),
            tooltip: widget.isPlaying ? '暂停 (空格)' : '播放 (空格)',
          ),
          SizedBox(width: gap),
          side(
            icon: BIcons.next,
            onTap: widget.onPlayNext,
            tip: '下一集',
          ),
        ],
      ),
    );
  }
}

/// 播放器顶部高质感微光导航栏 (包含返回、剧集标题、极光画质、比例切换、线路切换)
class BrandPlayerTopBar extends StatelessWidget {
  final String title;
  final String? episodeName;
  final String? serverName;
  final bool isEnhanced;
  final String aspectModeLabel;
  final VoidCallback onBack;
  final VoidCallback onToggleEnhance;
  final VoidCallback onToggleAspect;
  final VoidCallback? onSelectRoute;
  final bool isCompact;

  const BrandPlayerTopBar({
    super.key,
    required this.title,
    this.episodeName,
    this.serverName,
    required this.isEnhanced,
    required this.aspectModeLabel,
    required this.onBack,
    required this.onToggleEnhance,
    required this.onToggleAspect,
    this.onSelectRoute,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 16,
        vertical: isCompact ? 6 : 10,
      ),
      child: Row(
        children: [
          // 圆形磨砂返回键
          BrandPlayerButton(
            icon: BIcons.arrowLeft,
            onPressed: onBack,
            size: isCompact ? 34 : 38,
            iconSize: isCompact ? 18 : 20,
            tooltip: '返回',
          ),
          const SizedBox(width: 10),

          // 标题与剧集标签
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 13 : 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (episodeName != null && episodeName!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  BrandBadge(
                    label: episodeName!,
                    isGradient: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 极光超清画质增强按键
          BrandPlayerPill(
            leading: BrandIcon(
              BIcons.sparkles,
              size: isCompact ? 12 : 14,
              color: isEnhanced ? Colors.white : AppColors.gold,
            ),
            label: isEnhanced ? (isCompact ? '增强' : '极光增强') : (isCompact ? '原画' : '原画画质'),
            active: isEnhanced,
            isGradient: true,
            tooltip: '切换极光画质增强',
            onPressed: onToggleEnhance,
            fontSize: isCompact ? 10 : 11,
          ),
          const SizedBox(width: 6),

          // 画面比例胶囊
          BrandPlayerPill(
            leading: BrandIcon(
              BIcons.ratio,
              size: isCompact ? 12 : 14,
              color: Colors.white70,
            ),
            label: aspectModeLabel,
            tooltip: '画面比例切换',
            onPressed: onToggleAspect,
            fontSize: isCompact ? 10 : 11,
          ),
          // 线路胶囊 (仅在提供回调时显示)
          if (onSelectRoute != null) ...[
            const SizedBox(width: 6),
            BrandPlayerPill(
              leading: BrandIcon(
                BIcons.routes,
                size: isCompact ? 12 : 14,
                color: AppColors.primary400,
              ),
              label: serverName ?? '线路1',
              active: true,
              activeColor: AppColors.primary600,
              tooltip: '点击切换播放线路',
              onPressed: onSelectRoute,
              fontSize: isCompact ? 10 : 11,
            ),
          ],
        ],
      ),
    );
  }
}

/// 播放器悬浮磨砂底栏 (包含品牌渐变滑块、Mini播放、时间戳、弹幕开关、倍速选择、选集抽屉、全屏)
class BrandPlayerBottomDock extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final double bufferProgress;
  final bool isPlaying;
  final bool isFullscreen;
  final bool danmakuEnabled;
  final double speed;
  final ValueChanged<double> onSeek;
  final VoidCallback onTogglePlay;
  final VoidCallback? onPlayNext;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onSelectSpeed;
  final VoidCallback? onToggleDrawer;
  final VoidCallback onToggleFullscreen;
  final String Function(Duration) formatDuration;
  final bool isCompact;

  const BrandPlayerBottomDock({
    super.key,
    required this.position,
    required this.duration,
    required this.bufferProgress,
    required this.isPlaying,
    required this.isFullscreen,
    required this.danmakuEnabled,
    required this.speed,
    required this.onSeek,
    required this.onTogglePlay,
    required this.onPlayNext,
    required this.onToggleDanmaku,
    required this.onSelectSpeed,
    required this.onToggleDrawer,
    required this.onToggleFullscreen,
    required this.formatDuration,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxMs = (duration.inMilliseconds > 0 ? duration.inMilliseconds : 1)
        .toDouble();
    final currentMs =
        position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();

    return Container(
      margin: EdgeInsets.fromLTRB(
        isCompact ? 8 : 14,
        0,
        isCompact ? 8 : 14,
        isCompact ? 6 : 10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isCompact ? 14 : 18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 10 : 14,
              isCompact ? 4 : 6,
              isCompact ? 10 : 14,
              isCompact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(isCompact ? 14 : 18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 品牌流光进度条 (含缓冲层、渐变已播放层与发光游标)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: isCompact ? 3.0 : 3.5,
                    trackShape: BrandGradientSliderTrackShape(
                      gradient: AppColors.brandGradient,
                      bufferProgress: bufferProgress,
                      additionalActiveTrackHeight: 1.0,
                    ),
                    thumbShape: BrandSliderThumbShape(
                      radius: isCompact ? 5.5 : 6.5,
                      glowColor: AppColors.purple,
                      ringColor: AppColors.primary400,
                    ),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: isCompact ? 10.0 : 14.0,
                    ),
                    overlayColor: AppColors.primary500.withValues(alpha: 0.15),
                    activeTrackColor: AppColors.primary500,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                  ),
                  child: Slider(
                    value: currentMs,
                    min: 0.0,
                    max: maxMs,
                    onChanged: onSeek,
                  ),
                ),

                // 底部动作控制行
                Row(
                  children: [
                    // Mini 播放/暂停键
                    BrandPlayerButton(
                      icon: isPlaying
                          ? BIcons.pause
                          : BIcons.play,
                      onPressed: onTogglePlay,
                      size: isCompact ? 28 : 32,
                      iconSize: isCompact ? 16 : 18,
                      tooltip: isPlaying ? '暂停' : '播放',
                    ),
                    const SizedBox(width: 4),

                    // 下一集快捷键
                    if (onPlayNext != null) ...[
                      BrandPlayerButton(
                        icon: BIcons.next,
                        onPressed: onPlayNext,
                        size: isCompact ? 28 : 32,
                        iconSize: isCompact ? 16 : 18,
                        tooltip: '下一集',
                      ),
                      const SizedBox(width: 6),
                    ],

                    // 时间戳显示 (等宽优雅字形)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatDuration(position),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompact ? 10.5 : 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          ' / ${formatDuration(duration)}',
                          style: TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontSize: isCompact ? 10.5 : 12,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // 弹幕开关微胶囊
                    BrandPlayerPill(
                      leading: BrandIcon(
                        danmakuEnabled
                            ? BIcons.message
                            : BIcons.message,
                        size: isCompact ? 11 : 13,
                        color: danmakuEnabled
                            ? AppColors.rose
                            : Colors.white38,
                      ),
                      label: danmakuEnabled ? '弹幕开' : '弹幕关',
                      active: danmakuEnabled,
                      activeColor: AppColors.purple,
                      tooltip: '弹幕开关 (D)',
                      onPressed: onToggleDanmaku,
                      fontSize: isCompact ? 10 : 11,
                    ),
                    const SizedBox(width: 6),

                    // 倍速菜单胶囊
                    BrandPlayerPill(
                      label: speed == speed.roundToDouble()
                          ? '${speed.toInt()}.0x'
                          : ((speed * 10) % 1 == 0
                              ? '${speed.toStringAsFixed(1)}x'
                              : '${speed.toStringAsFixed(2)}x'),
                      active: speed != 1.0,
                      activeColor: AppColors.primary400,
                      tooltip: '播放速度',
                      onPressed: onSelectSpeed,
                      fontSize: isCompact ? 10 : 11,
                    ),
                    const SizedBox(width: 6),

                    // 选集抽屉按钮 (全屏或支持时)
                    if (onToggleDrawer != null) ...[
                      BrandPlayerPill(
                        leading: BrandIcon(
                          BIcons.playlist,
                          size: isCompact ? 13 : 15,
                          color: Colors.white70,
                        ),
                        label: '选集',
                        tooltip: '选集与线路',
                        onPressed: onToggleDrawer,
                        fontSize: isCompact ? 10 : 11,
                      ),
                      const SizedBox(width: 6),
                    ],

                    // 全屏切换按钮
                    BrandPlayerButton(
                      icon: isFullscreen
                          ? BIcons.fullscreenExit
                          : BIcons.fullscreen,
                      onPressed: onToggleFullscreen,
                      size: isCompact ? 28 : 32,
                      iconSize: isCompact ? 18 : 20,
                      tooltip: isFullscreen ? '退出全屏 (F)' : '进入全屏 (F)',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧边屏幕锁按键 (防误触设计)
class BrandPlayerScreenLock extends StatelessWidget {
  final bool isLocked;
  final VoidCallback onToggleLock;
  final bool isCompact;

  const BrandPlayerScreenLock({
    super.key,
    required this.isLocked,
    required this.onToggleLock,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: isCompact ? 10 : 16),
        child: BrandPlayerButton(
          icon: isLocked ? BIcons.lock : BIcons.unlock,
          onPressed: onToggleLock,
          size: isCompact ? 36 : 42,
          iconSize: isCompact ? 18 : 22,
          iconColor: isLocked ? AppColors.rose : Colors.white70,
          backgroundColor: isLocked
              ? AppColors.rose.withValues(alpha: 0.22)
              : Colors.black.withValues(alpha: 0.45),
          border: Border.all(
            color: isLocked
                ? AppColors.rose.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.2),
            width: 1.0,
          ),
          glow: isLocked,
          glowColor: AppColors.rose,
          tooltip: isLocked ? '屏幕已锁定，点击解锁' : '锁定屏幕 (防误触)',
        ),
      ),
    );
  }
}

/// 统一的播放器手势与状态 HUD 提示浮层
class BrandPlayerHUD extends StatelessWidget {
  final BrandIconData? icon;
  final String text;
  final double? progress; // 可选的 0.0 ~ 1.0 进度条显示 (用于音量、亮度)

  const BrandPlayerHUD({
    super.key,
    this.icon,
    required this.text,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary500.withValues(alpha: 0.45),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.purple.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      BrandIcon(icon!, color: AppColors.primary400, size: 22),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 120,
                    height: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 长按加速指示器 (如: >> 2.0x 快进中...)
class BrandPlayerSpeedBoostBadge extends StatelessWidget {
  final double speed;
  final bool isCompact;

  const BrandPlayerSpeedBoostBadge({
    super.key,
    required this.speed,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final speedStr = speed == speed.roundToDouble()
        ? '${speed.toInt()}.0'
        : speed.toStringAsFixed(1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 18,
            vertical: isCompact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary500.withValues(alpha: 0.5),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.purple.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppColors.brandGradient.createShader(bounds),
                child: BrandIcon(
                  BIcons.fastForward,
                  color: Colors.white,
                  size: isCompact ? 18 : 22,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${speedStr}x 快进中',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isCompact ? 12 : 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放器内嵌倍速调节浮层 (0.5x ~ 4.0x 连续/微调拖拽滑块 + 预设快捷胶囊)
class BrandPlayerSpeedPanel extends StatefulWidget {
  final double currentSpeed;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onClose;
  final bool isCompact;

  const BrandPlayerSpeedPanel({
    super.key,
    required this.currentSpeed,
    required this.onSpeedChanged,
    required this.onClose,
    this.isCompact = false,
  });

  @override
  State<BrandPlayerSpeedPanel> createState() => _BrandPlayerSpeedPanelState();
}

class _BrandPlayerSpeedPanelState extends State<BrandPlayerSpeedPanel> {
  late double _speed;
  static const List<double> _presets = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0,
    4.0,
  ];

  @override
  void initState() {
    super.initState();
    _speed = widget.currentSpeed.clamp(0.5, 4.0);
  }

  @override
  void didUpdateWidget(BrandPlayerSpeedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSpeed != oldWidget.currentSpeed) {
      _speed = widget.currentSpeed.clamp(0.5, 4.0);
    }
  }

  String _formatSpeed(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toInt()}.0x';
    } else if ((speed * 10) % 1 == 0) {
      return '${speed.toStringAsFixed(1)}x';
    } else {
      return '${speed.toStringAsFixed(2)}x';
    }
  }

  void _onSliderChanged(double value) {
    // 0.1 步长连续吸附
    final stepped = (value * 10).round() / 10.0;
    setState(() {
      _speed = stepped;
    });
    widget.onSpeedChanged(stepped);
  }

  void _onPresetTapped(double preset) {
    setState(() {
      _speed = preset;
    });
    widget.onSpeedChanged(preset);
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.isCompact;
    final width = isCompact ? 290.0 : 330.0;

    return GestureDetector(
      // 拦截手势，防止冒泡触发底层播放器手势
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: width,
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 14 : 18,
              vertical: isCompact ? 12 : 14,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary500.withValues(alpha: 0.35),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppColors.purple.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部标题、当前倍速大字与关闭按键
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandIcon(
                          BIcons.speed,
                          color: AppColors.primary400,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '播放倍速',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.purple.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            _formatSpeed(_speed),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        BrandPlayerButton(
                          icon: BIcons.close,
                          size: 26,
                          iconSize: 15,
                          onPressed: widget.onClose,
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 连续可拖拽滑块 (0.5x - 4.0x)
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4.0,
                    trackShape: const BrandGradientSliderTrackShape(
                      gradient: AppColors.brandGradient,
                    ),
                    thumbShape: const BrandSliderThumbShape(
                      radius: 7.0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14.0,
                    ),
                    activeTrackColor: AppColors.primary500,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                  ),
                  child: Slider(
                    value: _speed.clamp(0.5, 4.0),
                    min: 0.5,
                    max: 4.0,
                    divisions: 35, // 0.1 步长
                    onChanged: _onSliderChanged,
                  ),
                ),

                // 滑块端点标尺刻度提示 (0.5x / 1.0x 标准 / 2.0x / 4.0x 极速)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0.5x',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '1.0x 标准',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '2.0x',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '4.0x 极速',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 快捷预设按键 (8 个常用预设)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: _presets.map((preset) {
                    final isSelected = (_speed - preset).abs() < 0.04;
                    return InkWell(
                      onTap: () => _onPresetTapped(preset),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 9 : 12,
                          vertical: isCompact ? 5 : 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: isSelected ? AppColors.brandGradient : null,
                          color: isSelected
                              ? null
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : Colors.white.withValues(alpha: 0.12),
                            width: 0.8,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.purple
                                        .withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          _formatSpeed(preset),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: isCompact ? 11 : 12,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

