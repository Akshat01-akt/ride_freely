import 'package:flutter/material.dart';
import 'package:ride_core/ride_core.dart';

/// Brand block shown at the top of the login and register screens.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: AppColors.fuchsia, borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.directions_car_filled_rounded, color: AppColors.cream, size: 30),
        ),
        const SizedBox(height: 24),
        Text(title, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.cream)),
        const SizedBox(height: 8),
        Text(subtitle, style: text.bodyLarge?.copyWith(color: AppColors.beige)),
      ],
    );
  }
}
