import 'package:flutter/material.dart';

import '../../../core/core.dart';
import '../data/models.dart';

class DriverCard extends StatelessWidget {
  const DriverCard({super.key, required this.driver, required this.onTap});

  final DriverSummary driver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HoverSurface(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Hero(
              tag: 'driver-${driver.id}',
              child: InitialsAvatar(name: driver.name, size: 58),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          driver.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (driver.verified) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          color: AppColors.fuchsia,
                          size: 17,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  RatingBadge(
                    rating: driver.rating,
                    rides: driver.rides > 0 ? driver.rides : null,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (driver.distanceLabel != null) driver.distanceLabel!,
                      '${driver.experienceYears} yrs experience',
                    ].join(' • '),
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '₹${driver.hourlyRate.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      TextSpan(
                        text: '/hr',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AppButton(label: 'Book', compact: true, onPressed: onTap),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
