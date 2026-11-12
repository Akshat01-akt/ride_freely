import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:ride_core/ride_core.dart';

import 'fake_adapter.dart';

AuthController _controller(Handler h, MemoryTokenStorage storage) {
  final client = ApiClient(baseUrl: 'http://test', storage: storage, adapter: FakeAdapter(h));
  return AuthController(AuthRepository(client, UserRole.customer));
}

void main() {
  setUp(Get.reset);

  test('bootstrap without a stored token is unauthenticated', () async {
    final c = _controller((o) => (status: 500, body: {}), MemoryTokenStorage());
    await c.bootstrap();
    expect(c.status.value, AuthStatus.unauthenticated);
  });

  test('bootstrap with a valid token is authenticated and loads the profile', () async {
    final storage = MemoryTokenStorage();
    await storage.save(const TokenPair(accessToken: 'A', refreshToken: 'R'));
    final c = _controller((o) => (status: 200, body: {'full_name': 'Asha'}), storage);
    await c.bootstrap();
    expect(c.status.value, AuthStatus.authenticated);
    expect(c.profile['full_name'], 'Asha');
  });

  test('bootstrap with a rejected token is unauthenticated, not a crash', () async {
    final storage = MemoryTokenStorage();
    await storage.save(const TokenPair(accessToken: 'A', refreshToken: 'R'));
    final c = _controller((o) => (status: 401, body: {'detail': 'x'}), storage);
    await c.bootstrap();
    expect(c.status.value, AuthStatus.unauthenticated);
  });

  test('failed login sets the error and stays unauthenticated', () async {
    final c = _controller((o) => (status: 401, body: {'detail': 'Invalid phone or password'}), MemoryTokenStorage());
    final ok = await c.login('+919876543210', 'nope-nope');
    expect(ok, isFalse);
    expect(c.error.value, 'Invalid phone or password');
    expect(c.isLoading.value, isFalse);
  });

  test('successful login authenticates', () async {
    final c = _controller((o) {
      if (o.path == '/auth/customer/login') {
        return (status: 200, body: {'access_token': 'A', 'refresh_token': 'R', 'token_type': 'bearer'});
      }
      return (status: 200, body: {'full_name': 'Asha'});
    }, MemoryTokenStorage());
    expect(await c.login('+919876543210', 'password123'), isTrue);
    expect(c.status.value, AuthStatus.authenticated);
  });

  test('logout clears the session', () async {
    final storage = MemoryTokenStorage();
    await storage.save(const TokenPair(accessToken: 'A', refreshToken: 'R'));
    final c = _controller((o) => (status: 200, body: {}), storage);
    await c.logout();
    expect(c.status.value, AuthStatus.unauthenticated);
    expect(await storage.read(), isNull);
  });
}
