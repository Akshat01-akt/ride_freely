import 'package:get/get.dart';
import 'package:ride_core/ride_core.dart';

/// Repository that never touches the network.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({this.hasToken = false, this.loginError})
      : super(ApiClient(baseUrl: 'http://fake', storage: MemoryTokenStorage()), UserRole.customer);

  final bool hasToken;
  final String? loginError;
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
  Future<Map<String, dynamic>> me() async =>
      {'full_name': 'Asha Rao', 'phone': '+919876543210', 'email': null};

  @override
  Future<void> logout() async {}
}

AuthController installController(FakeAuthRepository repo) {
  Get.reset();
  return Get.put(AuthController(repo));
}
