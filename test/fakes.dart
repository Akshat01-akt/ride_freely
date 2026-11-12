import 'package:get/get.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/customer/data/models.dart';
import 'package:ride_freely/features/customer/data/sources.dart';

/// Continuous animations never settle, so tests run with the OS reduce-motion setting on.
void reduceMotionFor(WidgetTester t, {Size size = const Size(390, 844)}) {
  t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
  // Lists build lazily, so tests need a phone-sized window rather than the 800x600 default.
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

class FakeDriversSource implements DriversSource {
  FakeDriversSource(this.drivers);
  final List<DriverSummary> drivers;

  @override
  Future<List<DriverSummary>> nearby() async => drivers;
}

class FakeWalletSource implements WalletSource {
  FakeWalletSource({this.data = const WalletData(), this.bookingList = const []});
  final WalletData data;
  final List<BookingSummary> bookingList;

  @override
  Future<WalletData> load() async => data;

  @override
  Future<List<BookingSummary>> bookings() async => bookingList;
}


/// Repository that never touches the network.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository(
    UserRole role, {
    this.hasToken = false,
    this.loginError,
    this.verification = 'PENDING',
  }) : super(ApiClient(baseUrl: 'http://fake', storage: MemoryTokenStorage()), role);

  final bool hasToken;
  final String? loginError;
  final String verification;
  int loginCalls = 0;
  int registerCalls = 0;
  Map<String, dynamic>? lastRegister;

  @override
  Future<bool> hasSession() async => hasToken;

  @override
  Future<void> login(String phone, String password) async {
    loginCalls++;
    if (loginError != null) throw ApiException(loginError!, statusCode: 401);
  }

  @override
  Future<void> register(Map<String, dynamic> fields) async {
    registerCalls++;
    lastRegister = fields;
  }

  @override
  Future<Map<String, dynamic>> me() async => role == UserRole.driver
      ? {
          'full_name': 'Ravi Kumar',
          'phone': '+919876500000',
          'licence_number': 'DL-123',
          'experience_years': 6,
          'hourly_rate': '180.00',
          'verification_status': verification,
          'availability_status': 'OFFLINE',
          'rating': '0.00',
        }
      : {'full_name': 'Asha Rao', 'phone': '+919876543210', 'email': null};

  @override
  Future<void> logout() async {}
}

class Fakes {
  Fakes({
    UserRole? storedRole,
    FakeAuthRepository? customer,
    FakeAuthRepository? driver,
    this.onboardingDone = true,
    List<DriverSummary> drivers = const [],
    WalletSource? wallet,
  })  : driversSource = FakeDriversSource(drivers),
        walletSource = wallet ?? FakeWalletSource(),
        customer = customer ?? FakeAuthRepository(UserRole.customer),
        driver = driver ?? FakeAuthRepository(UserRole.driver),
        roleStore = MemoryRoleStore(storedRole);

  final bool onboardingDone;
  final FakeDriversSource driversSource;
  final WalletSource walletSource;
  final FakeAuthRepository customer;
  final FakeAuthRepository driver;
  final MemoryRoleStore roleStore;

  void install() {
    Get.reset();
    Get.put<RoleStore>(roleStore);
    Get.put<OnboardingStore>(MemoryOnboardingStore(onboardingDone));
    Get.put(DriversController(driversSource));
    Get.put(WalletController(walletSource));
    Get.put(AuthController(customer), tag: UserRole.customer.name);
    Get.put(AuthController(driver), tag: UserRole.driver.name);
  }
}
