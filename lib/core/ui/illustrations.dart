import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Side-view car drawn with vector shapes, so there are no image assets to ship.
class CarIllustration extends StatelessWidget {
  const CarIllustration({super.key, this.width = 220, this.body = AppColors.cream, this.glass});

  final double width;
  final Color body;
  final Color? glass;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, width * 0.46),
        painter: _CarPainter(body, glass ?? AppColors.charcoal),
      );
}

class _CarPainter extends CustomPainter {
  _CarPainter(this.body, this.glass);
  final Color body;
  final Color glass;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final bodyPaint = Paint()..color = body;
    final cabin = Path()
      ..moveTo(.22 * w, .52 * h)
      ..quadraticBezierTo(.28 * w, .12 * h, .42 * w, .10 * h)
      ..lineTo(.62 * w, .10 * h)
      ..quadraticBezierTo(.76 * w, .14 * h, .84 * w, .52 * h)
      ..close();
    canvas.drawPath(cabin, bodyPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(.02 * w, .46 * h, .96 * w, .34 * h), Radius.circular(.12 * h)),
      bodyPaint,
    );
    final window = Paint()..color = glass.withValues(alpha: 0.85);
    canvas.drawPath(
      Path()
        ..moveTo(.30 * w, .46 * h)
        ..quadraticBezierTo(.34 * w, .20 * h, .43 * w, .18 * h)
        ..lineTo(.50 * w, .18 * h)
        ..lineTo(.50 * w, .46 * h)
        ..close(),
      window,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.54 * w, .18 * h)
        ..lineTo(.62 * w, .18 * h)
        ..quadraticBezierTo(.72 * w, .22 * h, .77 * w, .46 * h)
        ..lineTo(.54 * w, .46 * h)
        ..close(),
      window,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(.90 * w, .54 * h, .07 * w, .08 * h), const Radius.circular(3)),
      Paint()..color = AppColors.fuchsia,
    );
    for (final x in [.24, .76]) {
      final c = Offset(x * w, .80 * h);
      canvas.drawCircle(c, .16 * h, Paint()..color = AppColors.black);
      canvas.drawCircle(c, .08 * h, Paint()..color = AppColors.beige);
    }
  }

  @override
  bool shouldRepaint(_CarPainter old) => old.body != body || old.glass != glass;
}

/// Abstract road-map backdrop for the tracking screen. It draws no location data.
class MapBackdrop extends StatelessWidget {
  const MapBackdrop({super.key, this.route});

  /// Optional route in 0..1 coordinates, drawn only when real points are supplied.
  final List<Offset>? route;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _MapPainter(route), size: Size.infinite);
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.route);
  final List<Offset>? route;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = AppColors.beige.withValues(alpha: 0.45));
    final road = Paint()
      ..color = AppColors.cream
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(0, s.height * i / 5 + math.sin(i) * 12), Offset(s.width, s.height * i / 5 - math.sin(i) * 12), road);
      canvas.drawLine(Offset(s.width * i / 5 + math.cos(i) * 10, 0), Offset(s.width * i / 5 - math.cos(i) * 10, s.height), road);
    }
    final r = route;
    if (r != null && r.length > 1) {
      final path = Path()..moveTo(r.first.dx * s.width, r.first.dy * s.height);
      for (final p in r.skip(1)) {
        path.lineTo(p.dx * s.width, p.dy * s.height);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.fuchsia
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.route != route;
}
