import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'brand_widgets.dart';

Color? memberColor(dynamic value) {
  final text = value?.toString() ?? '';
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) return null;
  return Color(int.parse('FF${text.substring(1)}', radix: 16));
}

class MemberAvatar extends StatefulWidget {
  final String avatar;
  final String frame;
  final double size;
  const MemberAvatar({
    super.key,
    this.avatar = '',
    this.frame = '',
    this.size = 56,
  });
  @override
  State<MemberAvatar> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends State<MemberAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(MemberAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    if (widget.avatar.endsWith('/pulse.svg')) {
      _animation.repeat(reverse: true);
    } else {
      _animation.stop();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builtin = widget.avatar.startsWith('/api/cosmetics/');
    final imageUrl = widget.avatar.startsWith('/')
        ? '${ApiService().baseUrl}${widget.avatar}'
        : widget.avatar;
    return Container(
      width: widget.size,
      height: widget.size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: memberColor(widget.frame) ?? const Color(0xFFE0E7FF),
          width: 3,
        ),
      ),
      child: ClipOval(
        child: builtin
            ? AnimatedBuilder(
                animation: _animation,
                builder: (context, _) => CustomPaint(
                  painter: _PlanetPainter(
                    widget.avatar.endsWith('/pulse.svg') ? _animation.value : 0,
                  ),
                ),
              )
            : widget.avatar.isEmpty
            ? const BrandLogo(symbolOnly: true)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) =>
                    const BrandLogo(symbolOnly: true),
              ),
      ),
    );
  }
}

class _PlanetPainter extends CustomPainter {
  final double pulse;
  _PlanetPainter(this.pulse);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), r = size.shortestSide / 2;
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF111827));
    canvas.drawCircle(
      center,
      r * (.54 + pulse * .06),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF22D3EE)],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 7);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 1.65, height: r * .5),
      Paint()
        ..color = const Color(0xFFF5D0FE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .06,
    );
    canvas.restore();
    canvas.drawCircle(
      Offset(size.width * .75, size.height * .25),
      r * .08,
      Paint()..color = const Color(0xFFFDE68A),
    );
  }

  @override
  bool shouldRepaint(_PlanetPainter oldDelegate) => pulse != oldDelegate.pulse;
}
