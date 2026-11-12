import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'tokens.dart';

/// The one page transition used everywhere: the new page fades and slides in from the right
/// while the page beneath it eases back and dims slightly. Off when reduced motion is on.
class AppPageTransition extends CustomTransition {
  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) return child;
    final enter = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    final exit = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOutCubic);
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 0.96).animate(exit),
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.6).animate(exit),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(enter),
          child: FadeTransition(opacity: enter, child: child),
        ),
      ),
    );
  }
}

/// Switches between tab bodies with a short slide: forwards from the right, backwards from the left.
class AnimatedTabSwitcher extends StatefulWidget {
  const AnimatedTabSwitcher({super.key, required this.index, required this.builder});

  final int index;
  final Widget Function(int index) builder;

  @override
  State<AnimatedTabSwitcher> createState() => _AnimatedTabSwitcherState();
}

class _AnimatedTabSwitcherState extends State<AnimatedTabSwitcher> {
  int _direction = 1;

  @override
  void didUpdateWidget(AnimatedTabSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _direction = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final page = KeyedSubtree(key: ValueKey(widget.index), child: widget.builder(widget.index));
    if (reduceMotion(context)) return page;
    return AnimatedSwitcher(
      duration: AppMotion.page,
      switchInCurve: AppMotion.curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(widget.index);
        final from = Offset((incoming ? 0.1 : -0.1) * _direction, 0);
        return SlideTransition(
          position: Tween<Offset>(begin: from, end: Offset.zero).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: page,
    );
  }
}

/// Gentle vertical float with a soft glow behind it. Static when reduced motion is on.
class FloatingGlow extends StatefulWidget {
  const FloatingGlow({super.key, required this.child, required this.color, this.size = 150});

  final Widget child;
  final Color color;
  final double size;

  @override
  State<FloatingGlow> createState() => _FloatingGlowState();
}

class _FloatingGlowState extends State<FloatingGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

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
  Widget build(BuildContext context) => ConstrainedBox(
        // A minimum, not a fixed size, so larger content (bigger text) is never clipped.
        constraints: BoxConstraints(minWidth: widget.size, minHeight: widget.size),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = Curves.easeInOut.transform(_c.value);
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: widget.size * (0.85 + 0.1 * t),
                  height: widget.size * (0.85 + 0.1 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [widget.color.withValues(alpha: 0.28), widget.color.withValues(alpha: 0)]),
                  ),
                ),
                Transform.translate(offset: Offset(0, -6 * t), child: child),
              ],
            );
          },
          child: widget.child,
        ),
      );
}
