import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';

import 'fake_adapter.dart';

const _pair = {'access_token': 'A1', 'refresh_token': 'R1', 'token_type': 'bearer'};

({ApiClient client, MemoryTokenStorage storage, FakeAdapter adapter}) _setup(Handler handler) {
  final storage = MemoryTokenStorage();
  final adapter = FakeAdapter(handler);
  final client = ApiClient(baseUrl: 'http://test/api/v1', storage: storage, adapter: adapter);
  return (client: client, storage: storage, adapter: adapter);
}

void main() {
  test('login saves tokens and hits the customer endpoint for the customer role', () async {
    final s = _setup((o) => (status: 200, body: _pair));
    final repo = AuthRepository(s.client, UserRole.customer);
    await repo.login('+919876543210', 'password123');
    expect(s.adapter.requests.single.path, '/auth/customer/login');
    expect((await s.storage.read())!.accessToken, 'A1');
  });

  test('login hits the driver endpoint for the driver role', () async {
    final s = _setup((o) => (status: 200, body: _pair));
    await AuthRepository(s.client, UserRole.driver).login('+919876543210', 'password123');
    expect(s.adapter.requests.single.path, '/auth/driver/login');
  });

  test('login failure surfaces the server detail and stores nothing', () async {
    final s = _setup((o) => (status: 401, body: {'detail': 'Invalid phone or password'}));
    final repo = AuthRepository(s.client, UserRole.customer);
    await expectLater(
      repo.login('+919876543210', 'bad'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid phone or password')),
    );
    expect(await s.storage.read(), isNull);
  });

  test('422 validation errors are flattened to the first message', () async {
    final s = _setup((o) => (
          status: 422,
          body: {
            'detail': [
              {'loc': ['body', 'phone'], 'msg': 'Value error, Enter a valid phone number'},
            ],
          },
        ));
    await expectLater(
      AuthRepository(s.client, UserRole.customer).register({'phone': 'x'}),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('valid phone number'))),
    );
  });

  test('expired access token triggers a single refresh then retries the request', () async {
    final s = _setup((o) {
      if (o.path == '/auth/refresh') {
        return (status: 200, body: {'access_token': 'A2', 'refresh_token': 'R2', 'token_type': 'bearer'});
      }
      return o.headers['Authorization'] == 'Bearer A2'
          ? (status: 200, body: {'full_name': 'Asha'})
          : (status: 401, body: {'detail': 'Invalid or expired token'});
    });
    await s.storage.save(const TokenPair(accessToken: 'A1', refreshToken: 'R1'));
    final me = await AuthRepository(s.client, UserRole.customer).me();
    expect(me['full_name'], 'Asha');
    expect(s.adapter.count('/auth/refresh'), 1);
    expect((await s.storage.read())!.refreshToken, 'R2');
  });

  test('refresh failure clears tokens and reports unauthorized', () async {
    final s = _setup((o) => (status: 401, body: {'detail': 'Invalid or expired token'}));
    await s.storage.save(const TokenPair(accessToken: 'A1', refreshToken: 'R1'));
    await expectLater(
      AuthRepository(s.client, UserRole.customer).me(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(await s.storage.read(), isNull);
  });

  test('a transient refresh failure (503) keeps the stored tokens', () async {
    final s = _setup((o) => o.path == '/auth/refresh'
        ? (status: 503, body: {'detail': 'busy'})
        : (status: 401, body: {'detail': 'Invalid or expired token'}));
    await s.storage.save(const TokenPair(accessToken: 'A1', refreshToken: 'R1'));
    await expectLater(AuthRepository(s.client, UserRole.customer).me(), throwsA(isA<ApiException>()));
    expect((await s.storage.read())!.refreshToken, 'R1');
  });

  test('requests have a receive timeout so a stalled server cannot spin forever', () {
    final s = _setup((o) => (status: 200, body: {}));
    expect(s.client.dio.options.receiveTimeout, isNotNull);
  });

  test('network failure becomes an ApiException with a friendly message', () async {
    final storage = MemoryTokenStorage();
    final client = ApiClient(
      baseUrl: 'http://test',
      storage: storage,
      adapter: FakeAdapter((o) => throw DioExceptionStub()),
    );
    await expectLater(
      AuthRepository(client, UserRole.driver).login('+919876543210', 'password123'),
      throwsA(isA<ApiException>()),
    );
  });
}

class DioExceptionStub implements Exception {}
