import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pressable.dart';
import 'tokens.dart';

enum AppButtonStyle { primary, secondary, light }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.style = AppButtonStyle.primary,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final AppButtonStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final primary = style == AppButtonStyle.primary;
    final light = style == AppButtonStyle.light;
    final fg = primary ? AppColors.cream : AppColors.fuchsia;
    final content = AnimatedSwitcher(
      duration: AppMotion.tap,
      child: loading
          ? SizedBox(
              key: const ValueKey('spinner'),
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: compact ? 14 : 16, fontWeight: FontWeight.w700))),
                if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: compact ? 16 : 20, color: fg)],
              ],
            ),
    );
    return Pressable(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: AppMotion.tap,
        opacity: onPressed == null ? 0.5 : 1,
        child: AnimatedContainer(
          duration: AppMotion.hover,
          height: compact ? 40 : 54,
          padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: primary ? AppGradients.fuchsia : null,
            color: light ? AppColors.cream : null,
            borderRadius: BorderRadius.circular(compact ? 14 : AppRadius.md),
            border: primary || light ? null : Border.all(color: AppColors.fuchsia, width: 1.5),
            boxShadow: primary && enabled ? softShadow(color: AppColors.fuchsia, alpha: 0.35, blur: 18, y: 8) : null,
          ),
          child: content,
        ),
      ),
    );
  }
}
