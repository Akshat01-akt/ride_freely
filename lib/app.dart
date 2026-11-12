import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/core.dart';
import 'features/auth/login_page.dart';
import 'features/customer/customer_home_shell.dart';
import 'features/customer/customer_register_page.dart';
import 'features/driver/driver_home_shell.dart';
import 'features/driver/driver_register_page.dart';
import 'features/role_select/role_select_page.dart';
import 'features/role_theme.dart';
import 'features/splash_page.dart';
import 'routes.dart';

class RideFreelyApp extends StatelessWidget {
  const RideFreelyApp({super.key});

  @override
  Widget build(BuildContext context) => GetMaterialApp(
        title: 'Ride Freely',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: Routes.splash,
        getPages: [
          GetPage(name: Routes.splash, page: SplashPage.new),
          GetPage(name: Routes.role, page: () => Theme(data: AppTheme.dark(), child: const RoleSelectPage())),
          for (final role in UserRole.values) ...[
            GetPage(name: Routes.login(role), page: () => RoleTheme(role: role, child: LoginPage(role: role))),
            GetPage(
              name: Routes.register(role),
              page: () => RoleTheme(
                role: role,
                child: role == UserRole.customer ? const CustomerRegisterPage() : const DriverRegisterPage(),
              ),
            ),
            GetPage(
              name: Routes.home(role),
              page: () => RoleTheme(
                role: role,
                child: role == UserRole.customer ? const CustomerHomeShell() : const DriverHomeShell(),
              ),
            ),
          ],
        ],
      );
}
