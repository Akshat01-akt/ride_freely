import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app.dart';
import 'core/core.dart';
import 'features/bookings/bookings.dart';
import 'features/customer/data/sources.dart';
import 'features/driver/availability_controller.dart';
import 'features/driver/data/driver_api.dart';
import 'features/driver/documents_controller.dart';
import 'features/driver/earnings.dart';

/// Fixes the backend address at build time. When empty the app uses a per-platform default,
/// and debug builds can change it from the login screen.
const _fixedBaseUrl = String.fromEnvironment('API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final defaultUrl = _fixedBaseUrl.isNotEmpty
      ? _fixedBaseUrl
      : defaultApiUrl(defaultTargetPlatform);
  final clients = <ApiClient>[];
  Get.put<RoleStore>(SecureRoleStore(), permanent: true);
  Get.put<OnboardingStore>(SecureOnboardingStore(), permanent: true);
  Get.put(
    WalletController(
      kUiPreview ? PreviewWalletSource() : BackendWalletSource(),
    ),
    permanent: true,
  );
  final repositories = <UserRole, AuthRepository>{};
  for (final role in UserRole.values) {
    // Separate token storage per role so a customer and a driver login never mix.
    final client = ApiClient(
      baseUrl: defaultUrl,
      storage: SecureTokenStorage(namespace: role.name),
    );
    clients.add(client);
    final repo = AuthRepository(client, role);
    repositories[role] = repo;
    Get.put(AuthController(repo), tag: role.name, permanent: true);
  }
  final serverConfig = ServerConfig(
    defaultUrl: defaultUrl,
    store: SecureServerStore(),
    clients: clients,
    honourSaved: _fixedBaseUrl.isEmpty,
  );
  await serverConfig.load();
  Get.put(serverConfig, permanent: true);
  final api = HttpDriverApi(repositories[UserRole.driver]!.client);
  Get.put<LocationService>(GeolocatorLocationService(), permanent: true);
  Get.put<DriverApi>(api, permanent: true);
  Get.put<DocumentPicker>(ImagePickerDocumentPicker(), permanent: true);
  Get.put(
    DriversController(
      kUiPreview
          ? PreviewDriversSource()
          : BackendDriversSource(
              repositories[UserRole.customer]!.client,
              Get.find<LocationService>(),
            ),
    ),
    permanent: true,
  );
  for (final role in UserRole.values) {
    Get.put(
      BookingsController(
        kUiPreview
            ? PreviewBookingsApi()
            : HttpBookingsApi(repositories[role]!.client),
      ),
      tag: role.name,
      permanent: true,
    );
  }
  Get.put(
    AvailabilityController(api, Get.find<LocationService>()),
    permanent: true,
  );
  Get.put(EarningsController(api), permanent: true);
  Get.put(
    DocumentsController(api, Get.find<DocumentPicker>()),
    permanent: true,
  );
  runApp(const RideFreelyApp());
}
