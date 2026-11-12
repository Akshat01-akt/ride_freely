import 'package:flutter/material.dart';

import '../core/core.dart';

/// Gives each interface its own look: customer is cream-led, driver is dark-grey-led.
class RoleTheme extends StatelessWidget {
  const RoleTheme({super.key, required this.role, required this.child});

  final UserRole role;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: role == UserRole.driver ? AppTheme.dark() : AppTheme.light(), child: child);
}
