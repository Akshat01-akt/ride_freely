import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pressable.dart';
import 'tokens.dart';

/// The four parts of the day the home screens reflect.
enum DayPart { morning, afternoon, evening, midnight }

/// morning 05:00-11:59, afternoon 12:00-16:59, evening 17:00-20:59, midnight 21:00-04:59.
DayPart dayPartFor(DateTime time) {
  final h = time.hour;
  if (h >= 5 && h < 12) return DayPart.morning;
  if (h >= 12 && h < 17) return DayPart.afternoon;
  if (h >= 17 && h < 21) return DayPart.evening;
  return DayPart.midnight;
}

extension on DayPart {
  String get greeting => switch (this) {
    DayPart.morning => 'Good morning',
    DayPart.afternoon => 'Good afternoon',
    DayPart.evening => 'Good evening',
    DayPart.midnight => 'Good night',
  };

  String get tagline => switch (this) {
    DayPart.morning => 'Rise and drive',
    DayPart.afternoon => 'Bright hours ahead',
    DayPart.evening => 'Golden hour rides',
    DayPart.midnight => 'Late-night trips, safely home',
  };

  IconData get icon => switch (this) {
    DayPart.morning => Icons.wb_twilight_rounded,
    DayPart.afternoon => Icons.wb_sunny_rounded,
    DayPart.evening => Icons.wb_twilight_rounded,
    DayPart.midnight => Icons.nightlight_round,
  };

  bool get darkSky => this == DayPart.evening || this == DayPart.midnight;

  List<Color> get sky => switch (this) {
    DayPart.morning => [AppColors.beige, AppColors.cream],
    DayPart.afternoon => [AppColors.cream, AppColors.beige],
    DayPart.evening => [AppColors.fuchsia, AppColors.charcoal],
    DayPart.midnight => [AppColors.black, AppColors.charcoal],
  };
}

/// A greeting card whose sky follows the time of day: a rising sun with drifting clouds in the morning,
/// a high sun in the afternoon, a setting sun in the evening, a moon and twinkling stars at night.
/// The scene loops slowly and holds still when reduced motion is on.
class DayPartCard extends StatefulWidget {
  const DayPartCard({super.key, required this.name, this.now});

  final String name;

  /// Fixed time for tests; null means the real clock, refreshed when the app comes back to the foreground.
  final DateTime? now;

  @override
  State<DayPartCard> createState() => _DayPartCardState();
}

class _DayPartCardState extends State<DayPartCard> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.now == null && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final part = dayPartFor(widget.now ?? DateTime.now());
    final first = widget.name.trim().split(RegExp(r'\s+')).first;
    final ink = part.darkSky ? AppColors.cream : AppColors.black;
    final sub = part.darkSky ? AppColors.cream.withValues(alpha: 0.85) : AppColors.charcoal;
    return AnimatedContainer(
      duration: AppMotion.page,
      curve: AppMotion.curve,
      constraints: const BoxConstraints(minHeight: 132),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: part.sky),
        boxShadow: softShadow(color: part.darkSky ? AppColors.fuchsia : AppColors.black, alpha: part.darkSky ? 0.25 : 0.08, blur: 24, y: 12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _ScenePainter(_c, part)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: AppMotion.page,
                          child: Icon(part.icon, key: ValueKey(part), color: part == DayPart.afternoon || part == DayPart.morning ? AppColors.fuchsia : AppColors.cream, size: 26),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          first.isEmpty ? part.greeting : '${part.greeting}, $first',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w800, height: 1.15),
                        ),
                        const SizedBox(height: 4),
                        Text(part.tagline, style: TextStyle(color: sub, height: 1.3)),
                      ],
                    ),
                  ),
                  // Leaves the right side of the card free for the sun or moon.
                  const SizedBox(width: 84),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.t, this.part) : super(repaint: t);

  final Animation<double> t;
  final DayPart part;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final phase = t.value * 2 * math.pi;
    switch (part) {
      case DayPart.morning:
        _glow(canvas, Offset(w - 52, h * 0.78), 90, AppColors.fuchsia, 0.35);
        _sun(canvas, Offset(w - 52, h * 0.78 - 4 * math.sin(phase)), 20, phase);
        _clouds(canvas, size, AppColors.cream, 0.9);
        _hills(canvas, size, AppColors.fuchsia.withValues(alpha: 0.18));
      case DayPart.afternoon:
        _glow(canvas, Offset(w - 48, h * 0.3), 100, AppColors.fuchsia, 0.28);
        _sun(canvas, Offset(w - 48, h * 0.3 + 3 * math.sin(phase)), 22, phase);
        _clouds(canvas, size, Colors.white, 0.95);
      case DayPart.evening:
        _glow(canvas, Offset(w - 52, h * 0.82), 110, AppColors.cream, 0.28);
        _sun(canvas, Offset(w - 52, h * 0.84 + 2 * math.sin(phase)), 22, phase, color: AppColors.cream);
        _clouds(canvas, size, AppColors.black, 0.18);
        _hills(canvas, size, AppColors.black.withValues(alpha: 0.5));
      case DayPart.midnight:
        _stars(canvas, size);
        _glow(canvas, Offset(w - 50, h * 0.32), 70, AppColors.cream, 0.18);
        _moon(canvas, Offset(w - 50, h * 0.32 + 3 * math.sin(phase)), 20);
    }
  }

  void _glow(Canvas canvas, Offset c, double r, Color color, double alpha) {
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _sun(Canvas canvas, Offset c, double r, double phase, {Color color = AppColors.fuchsia}) {
    final ray = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      final a = phase / 2 + i * 2 * math.pi / 10;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r + 6), c + Offset(math.cos(a), math.sin(a)) * (r + 12 + 2 * math.sin(phase * 2 + i)), ray);
    }
    canvas.drawCircle(c, r, Paint()..color = color);
  }

  void _moon(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = AppColors.cream);
    // Biting a second circle out of the first makes the crescent.
    canvas.drawCircle(c + Offset(r * 0.5, -r * 0.3), r * 0.9, Paint()..color = Color.lerp(AppColors.black, AppColors.charcoal, 0.3)!);
  }

  void _clouds(Canvas canvas, Size size, Color color, double alpha) {
    final paint = Paint()..color = color.withValues(alpha: alpha);
    const specs = [(0.0, 0.22, 1.0), (0.45, 0.5, 0.75), (0.8, 0.14, 0.6)];
    for (final (offset, y, scale) in specs) {
      const cloudWidth = 70.0;
      // t runs 0..1 and wraps, so the drift loops without a jump.
      final x = ((offset + t.value) % 1) * (size.width + cloudWidth * 2) - cloudWidth;
      final c = Offset(x, size.height * y);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(scale);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 8, 56, 16), const Radius.circular(8)), paint);
      canvas.drawCircle(const Offset(16, 8), 10, paint);
      canvas.drawCircle(const Offset(32, 4), 12, paint);
      canvas.restore();
    }
  }

  void _hills(Canvas canvas, Size size, Color color) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.86)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.7, size.width * 0.5, size.height * 0.86)
      ..quadraticBezierTo(size.width * 0.75, size.height * 1.0, size.width, size.height * 0.82)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _stars(Canvas canvas, Size size) {
    const spots = [
      (0.08, 0.2), (0.22, 0.62), (0.34, 0.14), (0.47, 0.5), (0.58, 0.82), (0.64, 0.2),
      (0.78, 0.7), (0.9, 0.55), (0.14, 0.86), (0.4, 0.34), (0.72, 0.1), (0.95, 0.9),
    ];
    for (var i = 0; i < spots.length; i++) {
      // Whole-number multiples of t keep each twinkle seamless across the loop.
      final a = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(2 * math.pi * (t.value * (1 + i % 3) + i / 12)));
      final p = Offset(size.width * spots[i].$1, size.height * spots[i].$2);
      final r = i.isEven ? 1.8 : 1.2;
      canvas.drawCircle(p, r, Paint()..color = AppColors.cream.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.part != part;
}

/// Soft icons drifting behind a screen: a car, a key, a pin, a route, a clock. Static when reduced motion is on.
class FloatingIconsBackground extends StatefulWidget {
  const FloatingIconsBackground({super.key, required this.child, this.dark = false});

  final Widget child;

  /// True on dark screens, where the icons are cream instead of fuchsia.
  final bool dark;

  @override
  State<FloatingIconsBackground> createState() => _FloatingIconsBackgroundState();
}

class _FloatingIconsBackgroundState extends State<FloatingIconsBackground> with SingleTickerProviderStateMixin {
  // x, y as fractions of the screen; size; whole-number speed so the loop is seamless.
  static const _icons = <(IconData, double, double, double, int)>[
    (Icons.directions_car_filled_rounded, 0.08, 0.12, 34, 1),
    (Icons.vpn_key_rounded, 0.78, 0.08, 26, 2),
    (Icons.place_rounded, 0.62, 0.3, 30, 1),
    (Icons.alt_route_rounded, 0.12, 0.42, 28, 2),
    (Icons.schedule_rounded, 0.86, 0.5, 26, 1),
    (Icons.local_taxi_rounded, 0.3, 0.66, 32, 2),
    (Icons.speed_rounded, 0.7, 0.74, 28, 1),
    (Icons.shield_rounded, 0.1, 0.86, 24, 2),
    (Icons.star_rounded, 0.5, 0.92, 22, 1),
  ];

  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18));

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
  Widget build(BuildContext context) {
    final color = widget.dark ? AppColors.cream : AppColors.fuchsia;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: LayoutBuilder(
                key: const Key('floating_icons'),
                builder: (_, box) => AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => Stack(
                    children: [
                      for (var i = 0; i < _icons.length; i++)
                        _drifting(i, box.biggest, color),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }

  Widget _drifting(int i, Size area, Color color) {
    final (icon, fx, fy, size, speed) = _icons[i];
    final a = 2 * math.pi * (_c.value * speed + i / _icons.length);
    return Positioned(
      left: area.width * fx + 14 * math.sin(a),
      top: area.height * fy + 18 * math.cos(a * 0.5 + i) ,
      child: Transform.rotate(
        angle: 0.25 * math.sin(a),
        child: Icon(icon, size: size, color: color.withValues(alpha: widget.dark ? 0.10 : 0.11)),
      ),
    );
  }
}

/// A rounded fuchsia tile with a glowing icon that tilts and lifts on hover and shrinks when pressed.
class GradientIconTile extends StatefulWidget {
  const GradientIconTile({super.key, required this.icon, required this.onTap, this.size = 62});

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  State<GradientIconTile> createState() => _GradientIconTileState();
}

class _GradientIconTileState extends State<GradientIconTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Pressable(
      onTap: widget.onTap,
      pressedScale: 0.92,
      child: AnimatedContainer(
        duration: AppMotion.hover,
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          gradient: AppGradients.fuchsia,
          borderRadius: BorderRadius.circular(widget.size * 0.32),
          boxShadow: softShadow(color: AppColors.fuchsia, alpha: _hover ? 0.45 : 0.28, blur: _hover ? 22 : 14, y: _hover ? 10 : 6),
        ),
        child: AnimatedRotation(
          turns: _hover ? 0.03 : 0,
          duration: AppMotion.hover,
          curve: AppMotion.emphasized,
          child: Icon(widget.icon, color: AppColors.cream, size: widget.size * 0.46),
        ),
      ),
    ),
  );
}
