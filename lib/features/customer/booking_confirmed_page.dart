import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';
import '../bookings/bookings.dart';

/// Shown right after a request is sent. The driver has not agreed yet, so this never says "confirmed".
class BookingConfirmedPage extends StatelessWidget {
  const BookingConfirmedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final booking = Get.arguments as Booking;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AnimatedGradientBackground(
        dark: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const SuccessCheck(),
                const SizedBox(height: 8),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 500),
                  child: Text('Request sent', style: text.headlineMedium),
                ),
                const SizedBox(height: 6),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 560),
                  child: Text(
                    'Waiting for ${booking.driverName} to accept. Requests expire after 10 minutes.',
                    textAlign: TextAlign.center,
                    style: text.bodyLarge,
                  ),
                ),
                const SizedBox(height: 24),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 640),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: softShadow(alpha: 0.08),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            InitialsAvatar(name: booking.driverName, size: 52),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                booking.driverName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 28, color: AppColors.beige),
                        _Row('When', formatWindow(booking.start, booking.end)),
                        const SizedBox(height: 8),
                        _Row('Total', rupees(booking.price)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 720),
                  child: AppButton(
                    label: 'View my bookings',
                    onPressed: () => Get.offAllNamed(
                      Routes.home(UserRole.customer),
                      arguments: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 780),
                  child: AppButton(
                    label: 'Back to home',
                    style: AppButtonStyle.secondary,
                    onPressed: () =>
                        Get.offAllNamed(Routes.home(UserRole.customer)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}
