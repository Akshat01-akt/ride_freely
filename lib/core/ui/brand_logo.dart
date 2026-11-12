import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Steering-wheel mark. [turns] rotates it (0..1 is one full turn).
class SteeringWheel extends StatelessWidget {
  const SteeringWheel({super.key, this.size = 72, this.turns = 0, this.ringColor = AppColors.fuchsia, this.hubColor});

  final double size;
  final double turns;
  final Color ringColor;
  final Color? hubColor;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: turns * 2 * math.pi,
        child: CustomPaint(size: Size.square(size), painter: _WheelPainter(ringColor, hubColor ?? ringColor)),
      );
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.ring, this.hub);
  final Color ring;
  final Color hub;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final stroke = size.width * 0.12;
    final p = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r - stroke / 2, p);
    // Three spokes: left, right and down, meeting at the hub.
    for (final a in [math.pi, 0.0, math.pi / 2]) {
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * (r - stroke), p..strokeWidth = stroke * 0.8);
    }
    canvas.drawCircle(c, r * 0.24, Paint()..color = hub);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.ring != ring || old.hub != hub;
}

/// Wheel plus "DriveRent" wordmark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 64, this.onDark = false, this.turns = 0, this.showWordmark = true});

  final double size;
  final bool onDark;
  final double turns;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? AppColors.cream : AppColors.black;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SteeringWheel(size: size, turns: turns),
        if (showWordmark) ...[
          SizedBox(height: size * 0.18),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Drive', style: TextStyle(color: fg)),
                const TextSpan(text: 'Rent', style: TextStyle(color: AppColors.fuchsia)),
              ],
            ),
            style: TextStyle(fontSize: size * 0.46, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
        ],
      ],
    );
  }
}
