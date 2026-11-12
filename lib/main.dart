import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app.dart';
import 'core/core.dart';
import 'features/customer/data/sources.dart';
import 'features/driver/availability_controller.dart';
import 'features/driver/data/driver_api.dart';
import 'features/driver/documents_controller.dart';

const _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2/api/v1');

void main() {
  Get.put<RoleStore>(SecureRoleStore(), permanent: true);
  Get.put<OnboardingStore>(SecureOnboardingStore(), permanent: true);
  Get.put(DriversController(kUiPreview ? PreviewDriversSource() : BackendDriversSource()), permanent: true);
  Get.put(WalletController(kUiPreview ? PreviewWalletSource() : BackendWalletSource()), permanent: true);
  final repositories = <UserRole, AuthRepository>{};
  for (final role in UserRole.values) {
    // Separate token storage per role so a customer and a driver login never mix.
    final client = ApiClient(baseUrl: _baseUrl, storage: SecureTokenStorage(namespace: role.name));
    final repo = AuthRepository(client, role);
    repositories[role] = repo;
    Get.put(AuthController(repo), tag: role.name, permanent: true);
  }
  final api = HttpDriverApi(repositories[UserRole.driver]!.client);
  Get.put<LocationService>(GeolocatorLocationService(), permanent: true);
  Get.put<DriverApi>(api, permanent: true);
  Get.put<DocumentPicker>(ImagePickerDocumentPicker(), permanent: true);
  Get.put(AvailabilityController(api, Get.find<LocationService>()), permanent: true);
  Get.put(DocumentsController(api, Get.find<DocumentPicker>()), permanent: true);
  runApp(const RideFreelyApp());
}
