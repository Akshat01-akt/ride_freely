import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../auth/auth_scaffold.dart';
import '../bookings/bookings.dart';

/// Booking requests for this driver: ones needing an answer or a trip action first, then history.
class RequestsTab extends StatelessWidget {
  const RequestsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final bookings = bookingsFor(UserRole.driver);
    final text = Theme.of(context).textTheme;
    return Obx(() {
      if (bookings.loading.value && bookings.items.isEmpty) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (var i = 0; i < 2; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ShimmerBox(height: 170, radius: 24),
              ),
          ],
        );
      }
      if (bookings.error.value != null) {
        return EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load requests',
          body: bookings.error.value!,
          action: AppButton(
            label: 'Try again',
            compact: true,
            onPressed: bookings.load,
          ),
        );
      }
      if (bookings.items.isEmpty) {
        return const EmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'No requests yet',
          body: 'Booking requests from nearby customers will show up here.',
        );
      }
      final active = bookings.upcoming, history = bookings.past;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          FadeSlideIn(child: Text('Requests', style: text.headlineSmall)),
          Obx(() => FormError(bookings.actionError.value)),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Active', style: text.titleMedium),
            const SizedBox(height: 10),
            for (var i = 0; i < active.length; i++)
              FadeSlideIn(
                delay: Duration(milliseconds: 60 * i),
                child: RequestCard(booking: active[i], controller: bookings),
              ),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('History', style: text.titleMedium),
            const SizedBox(height: 10),
            for (final b in history)
              RequestCard(booking: b, controller: bookings),
          ],
        ],
      );
    });
  }
}
