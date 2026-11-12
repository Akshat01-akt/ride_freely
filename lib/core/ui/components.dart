import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pressable.dart';
import 'tokens.dart';

/// Circle with the person's initials. Used wherever there is no uploaded photo yet.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 52, this.ring = false});

  final String name;
  final double size;
  final bool ring;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppGradients.fuchsia,
          border: ring ? Border.all(color: AppColors.cream, width: 3) : null,
          boxShadow: ring ? softShadow(alpha: 0.18) : null,
        ),
        child: Text(
          _initials,
          style: TextStyle(color: AppColors.cream, fontWeight: FontWeight.w800, fontSize: size * 0.36),
        ),
      );
}

/// Star plus rating that counts up when first shown.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.rating, this.rides, this.light = false});

  final double rating;
  final int? rides;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final fg = light ? AppColors.cream : AppColors.charcoal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, color: AppColors.fuchsia, size: 18),
        const SizedBox(width: 3),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: reduceMotion(context) ? rating : 0, end: rating),
          duration: AppMotion.success,
          curve: AppMotion.curve,
          builder: (_, v, _) => Text(v.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
        ),
        if (rides != null) Flexible(child: Text('  ($rides rides)', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: 0.65), fontSize: 12))),
      ],
    );
  }
}

/// Small status label; the dot pulses when [pulsing] and motion is allowed.
class StatusPill extends StatefulWidget {
  const StatusPill({super.key, required this.label, required this.color, this.pulsing = false});

  final String label;
  final Color color;
  final bool pulsing;

  @override
  State<StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<StatusPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.pulsing && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: widget.pulsing
                      ? [BoxShadow(color: widget.color.withValues(alpha: 0.5 * (1 - _c.value)), blurRadius: 2 + 8 * _c.value, spreadRadius: 4 * _c.value)]
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(widget.label, style: TextStyle(color: widget.color, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (actionLabel != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(actionLabel!, style: const TextStyle(color: AppColors.fuchsia, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      );
}

/// Friendly empty state; the icon bobs gently when motion is allowed.
class EmptyState extends StatefulWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -6 * Curves.easeInOut.transform(_c.value)),
                child: child,
              ),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.fuchsia.withValues(alpha: 0.10)),
                child: Icon(widget.icon, size: 40, color: AppColors.fuchsia),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(widget.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(widget.body, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), height: 1.4)),
            if (widget.action != null) ...[const SizedBox(height: AppSpacing.md), widget.action!],
          ],
        ),
      ),
    );
  }
}

/// Placeholder block with a moving highlight, shown while real data loads.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({super.key, this.width, this.height = 16, this.radius = 12});

  final double? width;
  final double height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + 3 * _c.value, 0),
              end: Alignment(-0.5 + 3 * _c.value, 0),
              colors: [AppColors.beige.withValues(alpha: 0.55), AppColors.beige.withValues(alpha: 0.9), AppColors.beige.withValues(alpha: 0.55)],
            ),
          ),
        ),
      );
}

/// Banner with a slowly shifting fuchsia gradient and floating circles.
class GradientBanner extends StatefulWidget {
  const GradientBanner({super.key, required this.child, this.padding = const EdgeInsets.all(22)});

  final Widget child;
  final EdgeInsets padding;

  @override
  State<GradientBanner> createState() => _GradientBannerState();
}

class _GradientBannerState extends State<GradientBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = Curves.easeInOut.transform(_c.value);
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                gradient: LinearGradient(
                  begin: Alignment(-1 + 0.6 * t, -1),
                  end: Alignment(1, 1 - 0.6 * t),
                  colors: [AppColors.fuchsia, Color.lerp(AppColors.fuchsia, AppColors.charcoal, 0.55)!],
                ),
                boxShadow: softShadow(color: AppColors.fuchsia, alpha: 0.28, blur: 26, y: 14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Stack(
                  children: [
                    Positioned(right: -30 + 14 * t, top: -34 + 10 * t, child: _circle(120, 0.10)),
                    Positioned(right: 40 - 12 * t, bottom: -48, child: _circle(96, 0.08)),
                    Positioned(left: -20, bottom: -30 + 8 * t, child: _circle(70, 0.07)),
                    Padding(padding: widget.padding, child: child),
                  ],
                ),
              ),
            );
          },
          child: widget.child,
        ),
      );

  static Widget _circle(double d, double a) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.cream.withValues(alpha: a)),
      );
}

class NavItem {
  const NavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating bottom navigation with an animated selected pill.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.items, required this.index, required this.onChanged});

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: dark ? AppColors.graphite : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: softShadow(alpha: dark ? 0.35 : 0.10, blur: 28, y: 12),
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Pressable(
                  onTap: () => onChanged(i),
                  hoverScale: 1.04,
                  child: AnimatedContainer(
                    duration: AppMotion.hover,
                    curve: AppMotion.curve,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: i == index ? AppColors.fuchsia.withValues(alpha: 0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: AppMotion.tap,
                          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                          child: Icon(
                            i == index ? items[i].selectedIcon : items[i].icon,
                            key: ValueKey(i == index),
                            color: i == index ? AppColors.fuchsia : scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 2),
                        AnimatedDefaultTextStyle(
                          duration: AppMotion.hover,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                            color: i == index ? AppColors.fuchsia : scheme.onSurface.withValues(alpha: 0.6),
                          ),
                          child: Text(items[i].label),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Circle that pops in with a check drawn stroke by stroke, plus a small burst of dots.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 96});

  final double size;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotion.success + const Duration(milliseconds: 200));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    reduceMotion(context) ? _c.value = 1 : _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size * 1.6,
        height: widget.size * 1.6,
        child: CustomPaint(painter: _CheckPainter(_c, widget.size)),
      );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.d) : super(repaint: t);
  final Animation<double> t;
  final double d;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final pop = Curves.easeOutBack.transform((t.value / 0.5).clamp(0.0, 1.0));
    canvas.drawCircle(c, d / 2 * pop, Paint()..color = AppColors.fuchsia);
    final draw = Curves.easeOut.transform(((t.value - 0.4) / 0.4).clamp(0.0, 1.0));
    final check = Path()
      ..moveTo(c.dx - d * 0.2, c.dy + d * 0.02)
      ..lineTo(c.dx - d * 0.05, c.dy + d * 0.17)
      ..lineTo(c.dx + d * 0.22, c.dy - d * 0.14);
    final metric = check.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * draw),
      Paint()
        ..color = AppColors.cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = d * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final burst = ((t.value - 0.45) / 0.55).clamp(0.0, 1.0);
    if (burst > 0 && burst < 1) {
      for (var i = 0; i < 10; i++) {
        final a = i * math.pi / 5;
        final dist = d * (0.62 + 0.38 * Curves.easeOut.transform(burst));
        canvas.drawCircle(
          c + Offset(math.cos(a), math.sin(a)) * dist,
          3.5 * (1 - burst) + 1,
          Paint()..color = (i.isEven ? AppColors.fuchsia : AppColors.beige).withValues(alpha: 1 - burst),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => false;
}

/// Tappable settings-style row used in profile menus.
class MenuTile extends StatelessWidget {
  const MenuTile({super.key, required this.icon, required this.title, required this.onTap, this.danger = false});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final color = danger ? AppColors.fuchsia : scheme.onSurface;
    return Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: dark ? AppColors.graphite : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: softShadow(alpha: dark ? 0.2 : 0.05, blur: 16, y: 6),
        ),
        child: Row(
          children: [
            Icon(icon, color: danger ? AppColors.fuchsia : color.withValues(alpha: 0.8)),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color))),
            if (!danger) Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
