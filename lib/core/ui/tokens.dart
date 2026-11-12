import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

abstract final class AppSpacing {
  static const double xs = 4, sm = 8, md = 16, lg = 24, xl = 32;
}

abstract final class AppRadius {
  static const double sm = 12, md = 16, lg = 24, xl = 32;
}

/// Shared animation timings and curves so every screen moves the same way.
abstract final class AppMotion {
  static const tap = Duration(milliseconds: 160);
  static const hover = Duration(milliseconds: 220);
  static const entrance = Duration(milliseconds: 450);
  static const page = Duration(milliseconds: 380);
  static const background = Duration(seconds: 8);
  static const success = Duration(milliseconds: 800);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutBack;
}

/// True when the user asked the OS to reduce motion; continuous animations must stop.
bool reduceMotion(BuildContext context) => MediaQuery.disableAnimationsOf(context);

abstract final class AppGradients {
  /// Fuchsia to a darker shade of the same hue.
  static LinearGradient get fuchsia => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.fuchsia, Color.lerp(AppColors.fuchsia, AppColors.black, 0.28)!],
      );

  static LinearGradient get dark => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.charcoal, Color.lerp(AppColors.charcoal, AppColors.black, 0.55)!],
      );
}

List<BoxShadow> softShadow({Color color = AppColors.black, double alpha = 0.08, double blur = 24, double y = 10}) =>
    [BoxShadow(color: color.withValues(alpha: alpha), blurRadius: blur, offset: Offset(0, y))];
