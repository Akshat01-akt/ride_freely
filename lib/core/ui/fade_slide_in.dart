import 'package:flutter/material.dart';

import 'tokens.dart';

/// Fades and slides its child up once when it first appears. Use [delay] to stagger siblings.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero, this.dy = 22});

  final Widget child;
  final Duration delay;
  final double dy;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _v;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + AppMotion.entrance;
    _c = AnimationController(vsync: this, duration: total);
    final begin = widget.delay.inMilliseconds / total.inMilliseconds;
    _v = CurvedAnimation(parent: _c, curve: Interval(begin, 1, curve: AppMotion.curve));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _v,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _v.value,
          child: Transform.translate(offset: Offset(0, (1 - _v.value) * widget.dy), child: child),
        ),
      );
}
