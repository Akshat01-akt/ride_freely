import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/core.dart';
import '../../../routes.dart';
import '../data/sources.dart';
import '../widgets/driver_card.dart';
import '../widgets/drivers_error.dart';
import '../widgets/service_card.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  void _openDrivers([String? mode]) => Get.toNamed(Routes.drivers, arguments: mode);

  @override
  Widget build(BuildContext context) {
    final auth = authFor(UserRole.customer);
    final drivers = Get.find<DriversController>();
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        FadeSlideIn(
          child: Obx(() {
            final name = '${auth.profile['full_name'] ?? ''}';
            return Row(
              children: [
                InitialsAvatar(name: name, size: 48, ring: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hello, ${name.split(' ').first}', style: text.titleLarge),
                      const SizedBox(height: 2),
                      Text('Where do you need a driver today?', style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 18),
        FadeSlideIn(
          delay: const Duration(milliseconds: 60),
          child: HoverSurface(
            onTap: _openDrivers,
            radius: AppRadius.md,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: AppColors.charcoal.withValues(alpha: 0.6)),
                const SizedBox(width: 10),
                Expanded(child: Text('Search drivers by name', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.charcoal.withValues(alpha: 0.6)))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 120),
          child: GradientBanner(
            child: Row(
              children: [
                Expanded(
                  flex: 11,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('Drive anywhere\nwith ease', style: TextStyle(color: AppColors.cream, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
                      ),
                      const SizedBox(height: 8),
                      Text('Book a professional driver in just a few taps.', style: TextStyle(color: AppColors.cream.withValues(alpha: 0.85), height: 1.35)),
                      const SizedBox(height: 16),
                      AppButton(label: 'Book now', icon: Icons.arrow_forward_rounded, compact: true, style: AppButtonStyle.light, onPressed: _openDrivers),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Expanded(flex: 9, child: FittedBox(child: CarIllustration(width: 170))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        FadeSlideIn(delay: const Duration(milliseconds: 180), child: const SectionHeader(title: 'Quick services')),
        const SizedBox(height: 14),
        FadeSlideIn(
          delay: const Duration(milliseconds: 220),
          child: Row(
            children: [
              Expanded(child: ServiceCard(icon: Icons.bolt_rounded, label: 'Book now', onTap: () => _openDrivers('Book now'))),
              Expanded(child: ServiceCard(icon: Icons.schedule_rounded, label: 'Hourly', onTap: () => _openDrivers('Hourly'))),
              Expanded(child: ServiceCard(icon: Icons.wb_sunny_rounded, label: 'Full day', onTap: () => _openDrivers('Full day'))),
              Expanded(child: ServiceCard(icon: Icons.event_rounded, label: 'Scheduled', onTap: () => _openDrivers('Scheduled'))),
            ],
          ),
        ),
        const SizedBox(height: 26),
        FadeSlideIn(delay: const Duration(milliseconds: 280), child: SectionHeader(title: 'Popular drivers', actionLabel: 'See all', onAction: _openDrivers)),
        const SizedBox(height: 12),
        Obx(() {
          if (drivers.loading.value) {
            return Column(children: [for (var i = 0; i < 2; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: ShimmerBox(height: 90, radius: 24))]);
          }
          if (drivers.error.value != null) return DriversError(controller: drivers);
          if (drivers.drivers.isEmpty) {
            return const EmptyState(
              icon: Icons.person_search_rounded,
              title: 'No drivers nearby yet',
              body: 'Verified drivers who are online will show up here.',
            );
          }
          final top = drivers.drivers.take(3).toList();
          return Column(
            children: [
              for (var i = 0; i < top.length; i++)
                FadeSlideIn(
                  delay: Duration(milliseconds: 320 + 70 * i),
                  child: DriverCard(driver: top[i], onTap: () => Get.toNamed(Routes.driverDetails, arguments: top[i])),
                ),
            ],
          );
        }),
      ],
    );
  }
}
