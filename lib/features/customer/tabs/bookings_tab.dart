import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/core.dart';
import '../../../routes.dart';
import '../../bookings/bookings.dart';
import '../../auth/auth_scaffold.dart';

class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  bool _upcoming = true;

  @override
  Widget build(BuildContext context) {
    final bookings = bookingsFor(UserRole.customer);
    return PollWhileVisible(
      controller: bookings,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(
            child: Text(
              'My bookings',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: Row(
              children: [
                _Segment(
                  label: 'Upcoming',
                  selected: _upcoming,
                  onTap: () => setState(() => _upcoming = true),
                ),
                const SizedBox(width: 10),
                _Segment(
                  label: 'Past',
                  selected: !_upcoming,
                  onTap: () => setState(() => _upcoming = false),
                ),
              ],
            ),
          ),
          Obx(() => FormError(bookings.actionError.value)),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(() {
              if (bookings.loading.value && bookings.items.isEmpty) {
                return Column(
                  children: [
                    for (var i = 0; i < 2; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: ShimmerBox(height: 150, radius: 24),
                      ),
                  ],
                );
              }
              if (bookings.error.value != null) {
                return EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load bookings',
                  body: bookings.error.value!,
                  action: AppButton(
                    label: 'Try again',
                    compact: true,
                    onPressed: bookings.load,
                  ),
                );
              }
              final items = _upcoming ? bookings.upcoming : bookings.past;
              if (items.isEmpty) {
                return EmptyState(
                  icon: _upcoming
                      ? Icons.event_available_rounded
                      : Icons.history_rounded,
                  title: _upcoming
                      ? 'No upcoming bookings'
                      : 'No past bookings',
                  body: _upcoming
                      ? 'Book a driver and your trip will appear here.'
                      : 'Completed and cancelled trips will be listed here.',
                  action: _upcoming
                      ? AppButton(
                          label: 'Find a driver',
                          compact: true,
                          onPressed: () => Get.toNamed(Routes.drivers),
                        )
                      : null,
                );
              }
              return RefreshIndicator(
                onRefresh: () => bookings.load(keepItems: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    for (var i = 0; i < items.length; i++)
                      FadeSlideIn(
                        delay: Duration(milliseconds: 80 * i),
                        child: BookingCard(
                          booking: items[i],
                          controller: bookings,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: AnimatedContainer(
      duration: AppMotion.hover,
      curve: AppMotion.curve,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? AppColors.fuchsia : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: selected
            ? softShadow(color: AppColors.fuchsia, alpha: 0.3, blur: 14, y: 6)
            : softShadow(alpha: 0.05, blur: 10, y: 4),
      ),
      child: AnimatedDefaultTextStyle(
        duration: AppMotion.hover,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.cream : AppColors.charcoal,
        ),
        child: Text(label),
      ),
    ),
  );
}
