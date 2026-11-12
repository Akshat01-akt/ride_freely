import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app.dart';
import 'core/core.dart';
import 'features/customer/data/sources.dart';

const _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2/api/v1');

void main() {
  Get.put<RoleStore>(SecureRoleStore(), permanent: true);
  Get.put<OnboardingStore>(SecureOnboardingStore(), permanent: true);
  Get.put(DriversController(kUiPreview ? PreviewDriversSource() : BackendDriversSource()), permanent: true);
  Get.put(WalletController(kUiPreview ? PreviewWalletSource() : BackendWalletSource()), permanent: true);
  for (final role in UserRole.values) {
    // Separate token storage per role so a customer and a driver login never mix.
    final client = ApiClient(baseUrl: _baseUrl, storage: SecureTokenStorage(namespace: role.name));
    Get.put(AuthController(AuthRepository(client, role)), tag: role.name, permanent: true);
  }
  runApp(const RideFreelyApp());
}
