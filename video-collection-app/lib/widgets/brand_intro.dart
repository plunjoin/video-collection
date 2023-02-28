import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Native adaptation of bllii-brand-kit/animation/bllii-intro.svg.
/// The original accent rect is a real progress track; null means unknown work.
class BrandIntro extends StatefulWidget {
  final double? progress;
  final double width;
  final bool onDark;
  final VoidCallback? onCompleted;
  const BrandIntro({
    super.key,
    this.progress,
    this.width = 440,
    this.onDark = false,
    this.onCompleted,
  });
  @override
  State<BrandIntro> createState() => _BrandIntroState();
}

class _BrandIntroState extends State<BrandIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onCompleted?.call();
      });
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _animation.value = 1;
      } else {
        _animation.forward();
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  double _phase(double start, double duration) => Curves.easeOutCubic.transform(
    ((_animation.value * 2.4 - start) / duration).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) {
    final dark =
        widget.onDark || Theme.of(context).brightness == Brightness.dark;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'bllii 正在加载',
      value: widget.progress == null
          ? null
          : '${(widget.progress! * 100).round()}%',
      child: SizedBox(
        width: widget.width,
        child: AspectRatio(
          aspectRatio: 960 / 540,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = constraints.maxWidth / 960;
              return AnimatedBuilder(
                animation: _animation,
                builder: (context, _) {
                  final arrive = _phase(0, 1);
                  final tagline = _phase(1.6, .8);
                  return Stack(
                    children: [
                      Positioned(
                        left: (172 - 43 * (1 - arrive)) * scale,
                        top: 135 * scale,
                        width: 256 * scale,
                        height: 214 * scale,
                        child: Opacity(
                          opacity: arrive,
                          child: Transform.rotate(
                            angle: -.14 * (1 - arrive),
                            child: Transform.scale(
                              scale: .86 + .14 * arrive,
                              child: Image.asset(
                                'assets/brand/bllii-symbol.png',
                                excludeFromSemantics: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final entry in [
                        (0.0, 160.0),
                        (173.0, 50.0),
                        (236.0, 50.0),
                        (302.0, 50.0),
                        (367.0, 50.0),
                      ].indexed)
                        Positioned(
                          left: (458 + entry.$2.$1 * .76) * scale,
                          top:
                              (166 +
                                  20 * (1 - _phase(.7 + entry.$1 * .1, .7))) *
                              scale,
                          width: entry.$2.$2 * .76 * scale,
                          height: 225 * .76 * scale,
                          child: Opacity(
                            opacity: _phase(.7 + entry.$1 * .1, .7),
                            child: Image.asset(
                              'assets/brand/bllii-intro-letter-${entry.$1}.png',
                              color: dark ? Colors.white : null,
                              excludeFromSemantics: true,
                            ),
                          ),
                        ),
                      Positioned(
                        top: (386 + 9 * (1 - tagline)) * scale,
                        left: 0,
                        right: 0,
                        child: Opacity(
                          opacity: tagline,
                          child: Text(
                            'More Stories, Together',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17 * scale,
                              letterSpacing: 4 * scale,
                              color: dark
                                  ? Colors.white70
                                  : const Color(0xFF747B9A),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 380 * scale,
                        top: 430 * scale,
                        width: 200 * scale,
                        height: math.max(3, 4 * scale),
                        child: Opacity(
                          opacity: _phase(1.45, .8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFF4B9FFF),
                                  Color(0xFF9A83FF),
                                  Color(0xFFFF89C7),
                                ],
                              ).createShader(bounds),
                              child: LinearProgressIndicator(
                                value: reduced && widget.progress == null
                                    ? 0
                                    : widget.progress?.clamp(0.0, 1.0),
                                color: Colors.white,
                                backgroundColor: Colors.white24,
                                minHeight: 4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
