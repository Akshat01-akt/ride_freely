import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';

/// Shared frame for login and both registration screens: animated background, logo, heading.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AnimatedGradientBackground(
        dark: dark,
        child: SafeArea(
          child: Column(
            children: [
              if (showBack)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(tooltip: 'Back', onPressed: Get.back, icon: const Icon(Icons.arrow_back_rounded)),
                )
              else
                const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeSlideIn(child: Center(child: BrandLogo(size: showBack ? 48 : 64, onDark: dark))),
                      const SizedBox(height: 24),
                      FadeSlideIn(delay: const Duration(milliseconds: 80), child: Text(title, style: text.headlineMedium)),
                      const SizedBox(height: 6),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 140),
                        child: Text(subtitle, style: text.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72))),
                      ),
                      const SizedBox(height: 24),
                      for (var i = 0; i < children.length; i++)
                        FadeSlideIn(delay: Duration(milliseconds: 200 + 50 * i), child: children[i]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated inline error shown under a form.
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return AnimatedSize(
      duration: AppMotion.hover,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(message!, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
    );
  }
}
