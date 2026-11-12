import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import 'data/models.dart';

/// Live tracking. It draws a route only when real (or, in UI preview, labelled sample) points
/// are supplied; otherwise it says it is waiting for the driver's live location.
class TrackingPage extends StatelessWidget {
  const TrackingPage({super.key});

  static const _previewRoute = [
    Offset(0.18, 0.82),
    Offset(0.18, 0.52),
    Offset(0.62, 0.52),
    Offset(0.62, 0.22),
  ];

  void _soon(BuildContext context, String what) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$what is not available yet.')));

  @override
  Widget build(BuildContext context) {
    final booking = Get.arguments as BookingSummary;
    final hasLocation = kUiPreview;
    final step = booking.status.index;
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Stack(
          children: [
            Positioned.fill(
              child: MapBackdrop(route: hasLocation ? _previewRoute : null),
            ),
            if (hasLocation) ...[
              Positioned(
                left: 0.62 * MediaQuery.sizeOf(context).width - 20,
                top: 0.22 * MediaQuery.sizeOf(context).height * 0.62 - 38,
                child: const Icon(
                  Icons.place_rounded,
                  color: AppColors.fuchsia,
                  size: 44,
                ),
              ),
            ] else
              Positioned(
                top: 120,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: softShadow(),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.location_searching_rounded,
                        color: AppColors.fuchsia,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text("Waiting for your driver's live location."),
                      ),
                    ],
                  ),
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Pressable(
                  onTap: Get.back,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      shape: BoxShape.circle,
                      boxShadow: softShadow(),
                    ),
                    child: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FadeSlideIn(
                dy: 60,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.xl),
                    ),
                    boxShadow: softShadow(alpha: 0.18, blur: 30, y: -6),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.beige,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          booking.status == BookingStatus.arrived
                              ? 'Your driver has arrived'
                              : 'Driver on the way…',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (booking.etaMinutes != null &&
                            booking.distanceKm != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Arriving in ${booking.etaMinutes} min • ${booking.distanceKm} km',
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            InitialsAvatar(name: booking.driver.name, size: 50),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking.driver.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  RatingBadge(rating: booking.driver.rating),
                                ],
                              ),
                            ),
                            _RoundAction(
                              icon: Icons.phone_rounded,
                              label: 'Call',
                              onTap: () => _soon(context, 'Calling'),
                            ),
                            const SizedBox(width: 10),
                            _RoundAction(
                              icon: Icons.chat_bubble_rounded,
                              label: 'Message',
                              onTap: () => _soon(context, 'Messaging'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _Stepper(step: step),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    pressedScale: 0.9,
    child: Tooltip(
      message: label,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.fuchsia.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.fuchsia),
      ),
    ),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});

  final int step;

  static const _labels = ['Assigned', 'On the way', 'Arrived'];

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(
      begin: reduceMotion(context) ? step.toDouble() : 0,
      end: step.toDouble(),
    ),
    duration: AppMotion.entrance + const Duration(milliseconds: 300),
    curve: AppMotion.curve,
    builder: (_, v, _) => Column(
      children: [
        SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (_, c) => Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  color: AppColors.beige,
                ),
                Container(
                  height: 3,
                  margin: const EdgeInsets.only(left: 9),
                  width: (c.maxWidth - 18) * (v / 2),
                  color: AppColors.fuchsia,
                ),
                for (var i = 0; i < 3; i++)
                  Positioned(
                    left: (c.maxWidth - 18) * i / 2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: v >= i - 0.01
                            ? AppColors.fuchsia
                            : AppColors.cream,
                        border: Border.all(
                          color: v >= i - 0.01
                              ? AppColors.fuchsia
                              : AppColors.beige,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 3; i++)
              Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: i == step ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
