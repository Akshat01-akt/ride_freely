import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import 'booking_models.dart';
import 'bookings_controller.dart';

String rupees(String amount) => '₹$amount';

/// Time, place, price and notes: the facts both the customer and the driver need to see.
class _Facts extends StatelessWidget {
  const _Facts({required this.booking, this.phone, this.phoneLabel});

  final Booking booking;
  final String? phone;
  final String? phoneLabel;

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.fuchsia),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.3))),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(Icons.schedule_rounded, formatWindow(booking.start, booking.end)),
        line(Icons.place_rounded, booking.address),
        if (booking.notes != null && booking.notes!.isNotEmpty)
          line(Icons.notes_rounded, booking.notes!),
        if (phone != null)
          line(Icons.phone_rounded, '${phoneLabel ?? 'Phone'}: $phone'),
        line(Icons.payments_rounded, 'Total ${rupees(booking.price)}'),
      ],
    );
  }
}

Color _pillColor(BookingState s) => switch (s) {
  BookingState.requested || BookingState.inProgress => AppColors.fuchsia,
  BookingState.accepted || BookingState.completed => AppColors.charcoal,
  _ => AppColors.graphite,
};

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.state});

  final String name;
  final BookingState state;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      InitialsAvatar(name: name, size: 44),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            StatusPill(
              label: state.label,
              color: _pillColor(state),
              pulsing:
                  state == BookingState.requested ||
                  state == BookingState.inProgress,
            ),
          ],
        ),
      ),
    ],
  );
}

class _Frame extends StatelessWidget {
  const _Frame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: HoverSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

/// A booking as the customer sees it, with Cancel while it can still be cancelled.
class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.controller,
  });

  final Booking booking;
  final BookingsController controller;

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text(
          'The driver will be told and the time slot is released.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.act(booking.id, BookingAction.cancel);
  }

  Future<void> _rate(BuildContext context) async {
    final stars = await showDialog<int>(context: context, builder: (_) => const _RatingDialog());
    if (stars != null) await controller.rate(booking.id, stars);
  }

  @override
  Widget build(BuildContext context) {
    final cancellable =
        booking.state == BookingState.requested ||
        booking.state == BookingState.accepted;
    return _Frame(
      children: [
        _Header(name: booking.driverName, state: booking.state),
        const SizedBox(height: 6),
        _Facts(
          booking: booking,
          phone: booking.driverPhone,
          phoneLabel: 'Driver',
        ),
        if (booking.state == BookingState.completed) ...[
          const SizedBox(height: 12),
          if (booking.rating != null)
            Row(
              children: [
                for (var i = 1; i <= 5; i++) Icon(i <= booking.rating! ? Icons.star_rounded : Icons.star_outline_rounded, size: 20, color: AppColors.fuchsia),
                const SizedBox(width: 8),
                Flexible(child: Text('You rated ${booking.rating} ${booking.rating == 1 ? 'star' : 'stars'}')),
              ],
            )
          else
            Obx(() => AppButton(
              label: 'Rate this trip',
              compact: true,
              icon: Icons.star_rounded,
              loading: controller.actingId.value == booking.id,
              onPressed: controller.actingId.value == null ? () => _rate(context) : null,
            )),
        ],
        if (cancellable) ...[
          const SizedBox(height: 12),
          Obx(
            () => AppButton(
              label: 'Cancel booking',
              compact: true,
              style: AppButtonStyle.secondary,
              loading: controller.actingId.value == booking.id,
              onPressed: controller.actingId.value == null
                  ? () => _cancel(context)
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// A booking as the driver sees it, with the one or two actions that make sense for its state.
class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.booking,
    required this.controller,
  });

  final Booking booking;
  final BookingsController controller;

  @override
  Widget build(BuildContext context) {
    final actions = switch (booking.state) {
      BookingState.requested => [
        ('Accept', BookingAction.accept, true),
        ('Decline', BookingAction.reject, false),
      ],
      BookingState.accepted => [('Start trip', BookingAction.start, true)],
      BookingState.inProgress => [
        ('Complete trip', BookingAction.complete, true),
      ],
      _ => const <(String, BookingAction, bool)>[],
    };
    return _Frame(
      children: [
        _Header(name: booking.customerName, state: booking.state),
        const SizedBox(height: 6),
        _Facts(
          booking: booking,
          phone: booking.customerPhone,
          phoneLabel: 'Customer',
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Obx(() {
            final busy = controller.actingId.value;
            return Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final (label, action, primary) in actions)
                  AppButton(
                    label: label,
                    compact: true,
                    style: primary
                        ? AppButtonStyle.primary
                        : AppButtonStyle.secondary,
                    loading: busy == booking.id && primary,
                    onPressed: busy == null
                        ? () => controller.act(booking.id, action)
                        : null,
                  ),
              ],
            );
          }),
        ],
      ],
    );
  }
}

class _RatingDialog extends StatefulWidget {
  const _RatingDialog();

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _stars = 0;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('How was your trip?'),
    content: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: i == 1 ? '1 star' : '$i stars',
            onPressed: () => setState(() => _stars = i),
            icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.fuchsia, size: 30),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
      TextButton(onPressed: _stars == 0 ? null : () => Navigator.of(context).pop(_stars), child: const Text('Send rating')),
    ],
  );
}
