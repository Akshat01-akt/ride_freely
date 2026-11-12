// Developer tool, not shipped: `flutter run -t lib/main_preview.dart --dart-define=UI_PREVIEW=true`
// seeds clearly labelled sample data and steps through every screen so the design can be reviewed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app.dart';
import 'core/core.dart';
import 'features/customer/data/sources.dart';
import 'routes.dart';

void main() {
  Get.put<RoleStore>(MemoryRoleStore(), permanent: true);
  Get.put<OnboardingStore>(MemoryOnboardingStore(false), permanent: true);
  Get.put(DriversController(PreviewDriversSource()), permanent: true);
  Get.put(WalletController(PreviewWalletSource()), permanent: true);
  for (final role in UserRole.values) {
    final client = ApiClient(baseUrl: 'http://preview.invalid', storage: MemoryTokenStorage());
    Get.put(AuthController(AuthRepository(client, role)), tag: role.name, permanent: true);
  }
  authFor(UserRole.customer).profile.assignAll({'full_name': 'Asha Rao', 'phone': '+919876543210'});
  authFor(UserRole.driver).profile.assignAll({
    'full_name': 'Ravi Kumar',
    'phone': '+919876500000',
    'licence_number': 'DL-0420110012345',
    'experience_years': 6,
    'hourly_rate': '180.00',
    'verification_status': 'PENDING',
    'rating': '0.00',
  });
  runApp(const RideFreelyApp());

  final driver = PreviewData.drivers.first;
  final booking = PreviewData.booking;
  final steps = <(String, String, Object?)>[
    ('splash', Routes.splash, null),
    ('onboarding', Routes.onboarding, null),
    ('role', Routes.role, null),
    ('customer_login', Routes.login(UserRole.customer), null),
    ('customer_register', Routes.register(UserRole.customer), null),
    ('driver_login', Routes.login(UserRole.driver), null),
    ('driver_register', Routes.register(UserRole.driver), null),
    ('customer_home', Routes.home(UserRole.customer), 0),
    ('drivers', Routes.drivers, 'Hourly'),
    ('driver_details', Routes.driverDetails, driver),
    ('confirmed', Routes.bookingConfirmed, booking),
    ('tracking', Routes.tracking, booking),
    ('bookings', Routes.home(UserRole.customer), 1),
    ('wallet', Routes.home(UserRole.customer), 2),
    ('profile', Routes.home(UserRole.customer), 3),
    ('driver_home', Routes.home(UserRole.driver), null),
  ];
  var i = 0;
  // Splash decides its own route after ~1.7s, so start stepping after that.
  Timer(const Duration(seconds: 4), () {
    Timer.periodic(const Duration(seconds: 5), (t) {
      if (i >= steps.length) return t.cancel();
      final s = steps[i++];
      if (s.$1 != 'splash') Get.offAllNamed(s.$2, arguments: s.$3);
      debugPrint('TOUR ${s.$1}');
    });
  });
}
