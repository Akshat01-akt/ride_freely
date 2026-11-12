import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'tokens.dart';

/// Slowly drifting gradient blobs behind a screen. Static when reduced motion is on.
class AnimatedGradientBackground extends StatefulWidget {
  const AnimatedGradientBackground({super.key, required this.child, this.dark = true});

  final Widget child;
  final bool dark;

  @override
  State<AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotion.background);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: widget.dark
                  ? AppGradients.dark
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.cream, AppColors.cream],
                    ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _BlobPainter(_c, widget.dark), size: Size.infinite),
          ),
          widget.child,
        ],
      );
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.t, this.dark) : super(repaint: t);

  final Animation<double> t;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final blobs = <(Color, double)>[
      (AppColors.fuchsia, dark ? 0.34 : 0.14),
      (dark ? AppColors.beige : AppColors.beige, dark ? 0.10 : 0.55),
      (AppColors.fuchsia, dark ? 0.18 : 0.08),
    ];
    for (var i = 0; i < blobs.length; i++) {
      final phase = t.value * 2 * math.pi + i * 2.1;
      final center = Offset(
        size.width * (0.15 + 0.35 * i + 0.10 * math.sin(phase)),
        size.height * (0.10 + 0.32 * i + 0.07 * math.cos(phase * 0.8)),
      );
      final radius = size.shortestSide * (0.55 + 0.12 * i);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [blobs[i].$1.withValues(alpha: blobs[i].$2), blobs[i].$1.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.dark != dark;
}
