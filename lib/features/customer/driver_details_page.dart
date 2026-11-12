import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';
import 'data/models.dart';
import 'data/sources.dart';

class DriverDetailsPage extends StatelessWidget {
  const DriverDetailsPage({super.key});

  DriverSummary get _driver => Get.arguments as DriverSummary;

  void _book(BuildContext context) {
    if (kUiPreview) {
      Get.toNamed(Routes.bookingConfirmed, arguments: BookingSummary(id: PreviewData.booking.id, driver: _driver, status: BookingStatus.assigned, etaMinutes: 5, distanceKm: 1.8));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking opens in the next release. Drivers cannot be booked yet.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _driver;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 270,
            backgroundColor: AppColors.charcoal,
            foregroundColor: AppColors.cream,
            leading: IconButton(tooltip: 'Back', onPressed: Get.back, icon: const Icon(Icons.arrow_back_rounded)),
            flexibleSpace: FlexibleSpaceBar(
              background: AnimatedGradientBackground(
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      Hero(tag: 'driver-${d.id}', child: InitialsAvatar(name: d.name, size: 112, ring: true)),
                      const SizedBox(height: 14),
                      Text(d.name, style: const TextStyle(color: AppColors.cream, fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      RatingBadge(rating: d.rating, rides: d.rides, light: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeSlideIn(
                    child: Row(
                      children: [
                        Expanded(child: Text('Hourly rate', style: text.bodyLarge)),
                        Text('₹${d.hourlyRate.toStringAsFixed(0)}/hr', style: text.headlineSmall?.copyWith(color: AppColors.fuchsia)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 70),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (d.verified) const StatusPill(label: 'Verified', color: AppColors.charcoal),
                        StatusPill(label: '${d.experienceYears} yrs experience', color: AppColors.charcoal),
                        StatusPill(label: d.available ? 'Available now' : 'Busy', color: d.available ? AppColors.fuchsia : AppColors.graphite, pulsing: d.available),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeSlideIn(delay: const Duration(milliseconds: 140), child: _Expandable(title: 'About', initiallyOpen: true, body: d.about ?? 'This driver has not added a description yet.')),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 200),
                    child: const _Expandable(title: 'How booking works', body: 'Choose a start time and duration. The driver confirms, then meets you at your pickup point and drives your car.'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AppButton(label: 'Book now', icon: Icons.arrow_forward_rounded, onPressed: d.available || !kUiPreview ? () => _book(context) : null),
        ),
      ),
    );
  }
}

class _Expandable extends StatefulWidget {
  const _Expandable({required this.title, required this.body, this.initiallyOpen = false});

  final String title;
  final String body;
  final bool initiallyOpen;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => setState(() => _open = !_open),
        hoverScale: 1.01,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md), boxShadow: softShadow(alpha: 0.05, blur: 14, y: 5)),
          child: AnimatedSize(
            duration: AppMotion.hover,
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    AnimatedRotation(turns: _open ? 0.5 : 0, duration: AppMotion.hover, child: const Icon(Icons.keyboard_arrow_down_rounded)),
                  ],
                ),
                if (_open) ...[const SizedBox(height: 8), Text(widget.body, style: const TextStyle(height: 1.45))],
              ],
            ),
          ),
        ),
      );
}
