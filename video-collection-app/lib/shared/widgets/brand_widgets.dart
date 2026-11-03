import 'dart:math' as math;

import '../ui/kit.dart';

import './brand_intro.dart';
import '../theme/brand_icons.dart';
export './brand_components.dart';
export './brand_player_controls.dart';

class BrandLogo extends StatelessWidget {
  final double width;
  final bool symbolOnly;
  const BrandLogo({super.key, this.width = 112, this.symbolOnly = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      symbolOnly
          ? 'assets/brand/bllii-symbol.png'
          : 'assets/brand/bllii-horizontal${dark ? '-white' : ''}.png',
      width: width,
      height: symbolOnly ? width : width * 0.388,
      fit: BoxFit.contain,
      semanticLabel: 'bllii',
    );
  }
}

/// 全局唯一的加载态。整页加载直接复用进入 App 时的那段品牌动画，
/// 需要塞进小图标位时用 [size] 走同源的环形流光，视觉语言保持一致。
class BrandLoading extends StatelessWidget {
  /// 小于等于 72 时走环形小尺寸，留空则使用启动动画。
  final double? size;
  final String? label;

  const BrandLoading({super.key, this.size, this.label});

  @override
  Widget build(BuildContext context) {
    final compact = size != null && size! <= 72;
    return Semantics(
      label: label ?? '正在加载',
      liveRegion: true,
      child: compact
          ? BrandSpinner(size: size!)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandIntro(width: size ?? 260),
                if (label != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    label!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// 品牌环形流光：与启动动画同一组渐变，用于按钮内、列表尾部等窄小位置。
class BrandSpinner extends StatefulWidget {
  final double size;
  const BrandSpinner({super.key, this.size = 24});

  @override
  State<BrandSpinner> createState() => _BrandSpinnerState();
}

class _BrandSpinnerState extends State<BrandSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final track = dark
        ? Colors.white.withValues(alpha: .12)
        : AppColors.primary600.withValues(alpha: .10);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _BrandArcPainter(
            turns: _controller.value,
            stroke: math.max(1.6, widget.size * .11),
            trackColor: track,
          ),
        ),
      ),
    );
  }
}

class _BrandArcPainter extends CustomPainter {
  final double turns;
  final double stroke;
  final Color trackColor;

  const _BrandArcPainter({
    required this.turns,
    required this.stroke,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    if (radius <= 0) return;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [
          Color(0x004B9FFF),
          Color(0xFF4B9FFF),
          Color(0xFF9A83FF),
          Color(0xFFFF89C7),
          Color(0x00FF89C7),
        ],
        stops: [0.0, .28, .58, .84, 1.0],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turns * 2 * math.pi);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.55, false, arc);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandArcPainter oldDelegate) =>
      oldDelegate.turns != turns ||
      oldDelegate.stroke != stroke ||
      oldDelegate.trackColor != trackColor;
}

/// 海报缺图时的兜底：按片名派生一个极浅的品牌色相渐变 + 首字水印。
/// 分类页大量条目没有封面，用纯灰块会让整面墙塌掉；这里让每个格子
/// 保留自己的色相和识别度，远看仍是一整片有节奏的浅色版面。
class BrandPosterFallback extends StatelessWidget {
  final String title;

  /// 是否显示首字水印。列表里的小缩略图可以不显示。
  final bool showGlyph;

  /// 强制走深色版本（放在深色底/虚化 hero 上时使用）。
  final bool? forceDark;

  const BrandPosterFallback({
    super.key,
    required this.title,
    this.showGlyph = true,
    this.forceDark,
  });

  static int _seedOf(String value) {
    var hash = 7;
    for (final rune in value.runes) {
      hash = (hash * 31 + rune) & 0x7fffffff;
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    final dark = forceDark ?? Theme.of(context).brightness == Brightness.dark;
    // 只取蓝→紫一段：粉色留给角标和主按钮，整墙都用粉会让强调色失效
    final hue = (216 + _seedOf(title) % 56).toDouble();
    final top = HSLColor.fromAHSL(
      1,
      hue,
      dark ? .26 : .58,
      dark ? .215 : .945,
    ).toColor();
    final bottom = HSLColor.fromAHSL(
      1,
      (hue + 18) % 360,
      dark ? .30 : .50,
      dark ? .155 : .885,
    ).toColor();
    final mark = dark ? Colors.white : const Color(0xFF1F2B42);
    final trimmed = title.trim();
    final glyph = trimmed.isEmpty
        ? ''
        : String.fromCharCode(trimmed.runes.first);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 120.0;
        // 宽条（资讯卡片封面）不能按宽度算字号，否则会撑满整个横带
        final base = constraints.hasBoundedHeight
            ? math.min(width, constraints.maxHeight)
            : width;
        final size = (base * .36).clamp(16.0, 76.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
          ),
          child: !showGlyph || glyph.isEmpty
              ? const SizedBox.expand()
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        glyph,
                        style: TextStyle(
                          fontSize: size,
                          height: 1.05,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -size * .02,
                          color: mark.withValues(alpha: dark ? .24 : .21),
                        ),
                      ),
                      if (base > 110) ...[
                        SizedBox(height: size * .16),
                        Container(
                          width: size * .42,
                          height: 1,
                          color: mark.withValues(alpha: dark ? .18 : .16),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class BrandButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final BrandIconData icon;
  const BrandButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon = BIcons.play,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? AppColors.brandGradient : null,
        color: enabled ? null : AppColors.lightBorder,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.brandSolid.withValues(alpha: 0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          shape: const StadiumBorder(),
          minimumSize: const Size(44, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.center,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BrandIcon(icon, size: 16, filled: true, monochrome: true),
            const SizedBox(width: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Web 风格品牌渐变主行动按钮 (全宽/定宽，带加载态与阴影)。
class BrandGradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool loading;
  final double height;
  final double? width;
  final BrandIconData? icon;

  const BrandGradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.loading = false,
    this.height = 44.0,
    this.width,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null && !loading;

    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: enabled ? AppColors.brandGradient : null,
        color: enabled
            ? null
            : (isDark ? AppColors.darkBorder : const Color(0xFFD5DCEB)),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.brandSolid.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: BrandSpinner(size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '处理中…',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    BrandIcon(icon!, size: 16, color: Colors.white, monochrome: true),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class BrandStoryBanner extends StatelessWidget {
  final VoidCallback? onTap;
  const BrandStoryBanner({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      // 与 BrandPageBanner 同约定:水平留白交给页面列表,这里只留上下节奏。
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? [const Color(0xFF34304F), const Color(0xFF263650)]
              : [
                  const Color(0xFFFFEFF8),
                  const Color(0xFFEEE9FF),
                  const Color(0xFFE8F1FF),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'bllii · 热爱收藏夹',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  '收藏每一份心动\n和喜欢的故事更近一步',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.7,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 12),
                  BrandButton(
                    onPressed: onTap,
                    label: '我的追番',
                    icon: BIcons.heart,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const BrandLogo(width: 80, symbolOnly: true),
        ],
      ),
    );
  }
}

/// 资讯/动态封面缺省占位组件（用于资讯中心列表与详情页）。
class ArticleCoverPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final double iconSize;

  const ArticleCoverPlaceholder({
    super.key,
    this.width,
    this.height,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: dark ? AppColors.darkBg : AppColors.primary50,
        child: Center(
          child: BrandIcon(
            BIcons.book,
            size: iconSize,
            color: AppColors.primary500,
          ),
        ),
      ),
    );
  }
}
