import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ride_core/ride_core.dart';

import '../../routes.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = Get.find<AuthController>();
      await auth.bootstrap();
      Get.offAllNamed(auth.status.value == AuthStatus.authenticated ? Routes.home : Routes.login);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.charcoal,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_car_filled_rounded, color: AppColors.fuchsia, size: 64),
              SizedBox(height: 16),
              Text(
                'Ride Freely',
                style: TextStyle(color: AppColors.cream, fontSize: 28, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
}
