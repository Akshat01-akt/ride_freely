import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../data/models.dart';

class BookingStatusCard extends StatelessWidget {
  const BookingStatusCard({super.key, required this.booking, required this.onTap});

  final BookingSummary booking;
  final VoidCallback onTap;

  static String labelFor(BookingStatus s) => switch (s) {
        BookingStatus.assigned => 'Driver assigned',
        BookingStatus.onTheWay => 'On the way',
        BookingStatus.arrived => 'Arrived',
      };

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: softShadow(alpha: 0.07)),
          child: Row(
            children: [
              InitialsAvatar(name: booking.driver.name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.driver.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Booking #${booking.id}', style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              StatusPill(label: labelFor(booking.status), color: AppColors.fuchsia, pulsing: booking.status == BookingStatus.onTheWay),
            ],
          ),
        ),
      );
}
