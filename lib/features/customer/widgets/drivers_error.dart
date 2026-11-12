import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/core.dart';
import '../data/sources.dart';

/// Shown instead of the driver list when it could not be loaded.
class DriversError extends StatelessWidget {
  const DriversError({super.key, required this.controller});

  final DriversController controller;

  @override
  Widget build(BuildContext context) {
    final problem = controller.problem.value;
    final needsSettings =
        problem == LocationProblem.deniedForever ||
        problem == LocationProblem.servicesOff;
    return EmptyState(
      icon: problem != null
          ? Icons.location_off_rounded
          : Icons.cloud_off_rounded,
      title: problem != null
          ? 'We need your location'
          : 'Could not load drivers',
      body: controller.error.value ?? '',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (needsSettings)
            AppButton(
              label: 'Open settings',
              compact: true,
              onPressed: () => Get.find<LocationService>().openSettings(),
            ),
          if (needsSettings) const SizedBox(height: 8),
          AppButton(
            label: 'Try again',
            compact: true,
            style: needsSettings
                ? AppButtonStyle.secondary
                : AppButtonStyle.primary,
            onPressed: controller.load,
          ),
        ],
      ),
    );
  }
}
