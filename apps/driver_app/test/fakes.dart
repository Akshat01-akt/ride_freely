import 'package:get/get.dart';
import 'package:ride_core/ride_core.dart';

/// Repository that never touches the network.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({this.hasToken = false, this.loginError, this.verification = 'PENDING'})
      : super(ApiClient(baseUrl: 'http://fake', storage: MemoryTokenStorage()), UserRole.driver);

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
  Future<Map<String, dynamic>> me() async => {
        'full_name': 'Ravi Kumar',
        'phone': '+919876500000',
        'licence_number': 'DL-123',
        'experience_years': 6,
        'hourly_rate': '180.00',
        'verification_status': verification,
        'availability_status': 'OFFLINE',
        'rating': '0.00',
      };

  @override
  Future<void> logout() async {}
}

AuthController installController(FakeAuthRepository repo) {
  Get.reset();
  return Get.put(AuthController(repo));
}
