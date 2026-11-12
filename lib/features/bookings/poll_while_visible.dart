import 'package:flutter/material.dart';

import 'bookings_controller.dart';

/// Keeps [controller]'s list fresh while [child] is on screen: not while another screen or dialog covers it,
/// and not while the app is in the background.
class PollWhileVisible extends StatefulWidget {
  const PollWhileVisible({super.key, required this.controller, required this.child});

  final BookingsController controller;
  final Widget child;

  @override
  State<PollWhileVisible> createState() => _PollWhileVisibleState();
}

class _PollWhileVisibleState extends State<PollWhileVisible> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.attach(this, visible: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.setAppActive(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      widget.controller.setAppActive(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
