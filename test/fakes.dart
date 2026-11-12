import 'package:get/get.dart';
import 'package:ride_freely/core/core.dart';

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
  Fakes({UserRole? storedRole, FakeAuthRepository? customer, FakeAuthRepository? driver})
      : customer = customer ?? FakeAuthRepository(UserRole.customer),
        driver = driver ?? FakeAuthRepository(UserRole.driver),
        roleStore = MemoryRoleStore(storedRole);

  final FakeAuthRepository customer;
  final FakeAuthRepository driver;
  final MemoryRoleStore roleStore;

  void install() {
    Get.reset();
    Get.put<RoleStore>(roleStore);
    Get.put(AuthController(customer), tag: UserRole.customer.name);
    Get.put(AuthController(driver), tag: UserRole.driver.name);
  }
}
