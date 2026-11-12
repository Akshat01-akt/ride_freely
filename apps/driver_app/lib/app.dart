import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ride_core/ride_core.dart';

import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/splash_page.dart';
import 'features/home/home_shell.dart';
import 'routes.dart';

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) => GetMaterialApp(
        title: 'Ride Freely',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        initialRoute: Routes.splash,
        getPages: [
          GetPage(name: Routes.splash, page: SplashPage.new),
          GetPage(name: Routes.login, page: LoginPage.new),
          GetPage(name: Routes.register, page: RegisterPage.new),
          GetPage(name: Routes.home, page: HomeShell.new),
        ],
      );
}
