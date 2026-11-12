import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';
import 'data/models.dart';

class BookingConfirmedPage extends StatelessWidget {
  const BookingConfirmedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final booking = Get.arguments as BookingSummary;
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
                FadeSlideIn(delay: const Duration(milliseconds: 500), child: Text('Booking confirmed!', style: text.headlineMedium)),
                const SizedBox(height: 6),
                FadeSlideIn(delay: const Duration(milliseconds: 560), child: Text('Your driver has been booked successfully.', style: text.bodyLarge)),
                const SizedBox(height: 24),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 640),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: softShadow(alpha: 0.08)),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Hero(tag: 'driver-${booking.driver.id}', child: InitialsAvatar(name: booking.driver.name, size: 52)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(booking.driver.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  Text('₹${booking.driver.hourlyRate.toStringAsFixed(0)}/hr'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [const Text('Booking ID'), Text('#${booking.id}', style: const TextStyle(fontWeight: FontWeight.w800))],
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                FadeSlideIn(delay: const Duration(milliseconds: 720), child: AppButton(label: 'Track ride', onPressed: () => Get.toNamed(Routes.tracking, arguments: booking))),
                const SizedBox(height: 12),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 780),
                  child: AppButton(label: 'Back to home', style: AppButtonStyle.secondary, onPressed: () => Get.offAllNamed(Routes.home(UserRole.customer))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
