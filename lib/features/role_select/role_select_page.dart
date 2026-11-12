import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';

class RoleSelectPage extends StatelessWidget {
  const RoleSelectPage({super.key});

  Future<void> _choose(UserRole role) async {
    await Get.find<RoleStore>().save(role);
    Get.offAllNamed(Routes.login(role));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AnimatedGradientBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const FadeSlideIn(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BrandLogo(size: 56, onDark: true),
                ),
              ),
              const SizedBox(height: 28),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  'Welcome to\nDriveRent',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 8),
              FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: Text(
                  'How would you like to use the app?',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: AppColors.beige),
                ),
              ),
              const SizedBox(height: 32),
              FadeSlideIn(
                delay: const Duration(milliseconds: 220),
                child: _RoleCard(
                  key: const Key('role_customer'),
                  icon: Icons.key_rounded,
                  title: 'I need a driver',
                  body:
                      'Book a verified driver for your own car, by the hour or for the full day.',
                  background: AppColors.cream,
                  foreground: AppColors.charcoal,
                  onTap: () => _choose(UserRole.customer),
                ),
              ),
              const SizedBox(height: 16),
              FadeSlideIn(
                delay: const Duration(milliseconds: 320),
                child: _RoleCard(
                  key: const Key('role_driver'),
                  icon: Icons.drive_eta_rounded,
                  title: "I'm a driver",
                  body:
                      'Register, get verified and earn from hourly and full-day bookings.',
                  background: AppColors.fuchsia,
                  foreground: AppColors.cream,
                  onTap: () => _choose(UserRole.driver),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverSurface(
    onTap: onTap,
    color: background,
    highlight: background == AppColors.fuchsia
        ? AppColors.cream
        : AppColors.fuchsia,
    padding: const EdgeInsets.all(22),
    child: Row(
      children: [
        Icon(icon, size: 36, color: foreground),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.85),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.arrow_forward_rounded, color: foreground),
      ],
    ),
  );
}
