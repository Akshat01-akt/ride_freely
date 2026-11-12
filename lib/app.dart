import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/core.dart';
import 'features/auth/login_page.dart';
import 'features/customer/book_page.dart';
import 'features/customer/booking_confirmed_page.dart';
import 'features/customer/customer_home_shell.dart';
import 'features/customer/driver_details_page.dart';
import 'features/customer/drivers_page.dart';
import 'features/customer/tracking_page.dart';
import 'features/customer/customer_register_page.dart';
import 'features/driver/documents_page.dart';
import 'features/driver/driver_home_shell.dart';
import 'features/driver/driver_register_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/role_select/role_select_page.dart';
import 'features/role_theme.dart';
import 'features/splash_page.dart';
import 'routes.dart';

class RideFreelyApp extends StatelessWidget {
  const RideFreelyApp({super.key});

  @override
  Widget build(BuildContext context) => GetMaterialApp(
    title: 'DriveRent',
    customTransition: AppPageTransition(),
    transitionDuration: AppMotion.page,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    initialRoute: Routes.splash,
    getPages: [
      GetPage(name: Routes.splash, page: SplashPage.new),
      GetPage(name: Routes.onboarding, page: OnboardingPage.new),
      GetPage(
        name: Routes.documents,
        page: () =>
            RoleTheme(role: UserRole.driver, child: const DocumentsPage()),
      ),
      GetPage(
        name: Routes.drivers,
        page: () =>
            RoleTheme(role: UserRole.customer, child: const DriversPage()),
      ),
      GetPage(
        name: Routes.driverDetails,
        page: () => RoleTheme(
          role: UserRole.customer,
          child: const DriverDetailsPage(),
        ),
      ),
      GetPage(
        name: Routes.book,
        page: () => RoleTheme(role: UserRole.customer, child: const BookPage()),
      ),
      GetPage(
        name: Routes.bookingConfirmed,
        page: () => RoleTheme(
          role: UserRole.customer,
          child: const BookingConfirmedPage(),
        ),
      ),
      GetPage(
        name: Routes.tracking,
        page: () =>
            RoleTheme(role: UserRole.customer, child: const TrackingPage()),
      ),
      GetPage(
        name: Routes.role,
        page: () => Theme(data: AppTheme.dark(), child: const RoleSelectPage()),
      ),
      for (final role in UserRole.values) ...[
        GetPage(
          name: Routes.login(role),
          page: () => RoleTheme(
            role: role,
            child: LoginPage(role: role),
          ),
        ),
        GetPage(
          name: Routes.register(role),
          page: () => RoleTheme(
            role: role,
            child: role == UserRole.customer
                ? const CustomerRegisterPage()
                : const DriverRegisterPage(),
          ),
        ),
        GetPage(
          name: Routes.home(role),
          page: () => RoleTheme(
            role: role,
            child: role == UserRole.customer
                ? const CustomerHomeShell()
                : const DriverHomeShell(),
          ),
        ),
      ],
    ],
  );
}
