import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pressable.dart';
import 'tokens.dart';

/// A card that lifts on mouse hover (stronger shadow, highlighted border) and, when [onTap]
/// is set, shrinks slightly on press. Touch devices get the press feedback; hover never carries meaning alone.
class HoverSurface extends StatefulWidget {
  const HoverSurface({
    super.key,
    required this.child,
    this.onTap,
    this.radius = AppRadius.lg,
    this.padding = EdgeInsets.zero,
    this.color,
    this.highlight = AppColors.fuchsia,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color highlight;

  @override
  State<HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<HoverSurface> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = AnimatedContainer(
      duration: reduceMotion(context) ? Duration.zero : AppMotion.hover,
      curve: AppMotion.curve,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? (dark ? AppColors.graphite : Colors.white),
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: widget.highlight.withValues(alpha: _hover ? 0.4 : 0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: _hover ? 0.16 : (dark ? 0.25 : 0.07)),
            blurRadius: _hover ? 32 : 20,
            offset: Offset(0, _hover ? 16 : 8),
          ),
        ],
      ),
      child: widget.child,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.onTap == null ? surface : Pressable(onTap: widget.onTap, hoverScale: 1.01, child: surface),
    );
  }
}

/// Text link with an underline that grows from the left on hover.
class HoverLink extends StatefulWidget {
  const HoverLink({super.key, required this.label, required this.onTap, this.color = AppColors.fuchsia});

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  State<HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<HoverLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Pressable(
          onTap: widget.onTap,
          hoverScale: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(widget.label, style: TextStyle(color: widget.color, fontWeight: FontWeight.w700)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _hover ? 1 : 0),
                    duration: reduceMotion(context) ? Duration.zero : AppMotion.hover,
                    curve: AppMotion.curve,
                    builder: (_, v, _) => FractionallySizedBox(
                      key: const Key('hover_link_underline'),
                      alignment: Alignment.centerLeft,
                      widthFactor: v,
                      child: Container(height: 2, decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
