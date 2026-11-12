import 'package:flutter/material.dart';

import 'bookings_controller.dart';

/// Keeps [controller]'s list fresh while [child] is on screen and the app is in the foreground.
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
    widget.controller.startPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.startPolling();
      widget.controller.load(keepItems: true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      widget.controller.stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
