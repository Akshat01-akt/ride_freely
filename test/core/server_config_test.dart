import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';

ApiClient _client([String url = 'http://old/api/v1']) => ApiClient(baseUrl: url, storage: MemoryTokenStorage());

void main() {
  group('normalising what the user types', () {
    const cases = {
      '192.168.29.218': 'http://192.168.29.218/api/v1',
      '  192.168.29.218  ': 'http://192.168.29.218/api/v1',
      '192.168.29.218:8000': 'http://192.168.29.218:8000/api/v1',
      'http://192.168.29.218': 'http://192.168.29.218/api/v1',
      'http://192.168.29.218/': 'http://192.168.29.218/api/v1',
      'http://192.168.29.218/api/v1': 'http://192.168.29.218/api/v1',
      'http://192.168.29.218/api/v1/': 'http://192.168.29.218/api/v1',
      'https://api.driverent.example': 'https://api.driverent.example/api/v1',
      'localhost': 'http://localhost/api/v1',
    };
    cases.forEach((input, expected) {
      test('"$input" becomes $expected', () => expect(normalizeServerUrl(input), expected));
    });

    for (final bad in ['', '   ', 'ftp://example.com', 'http://', 'http:// bad host', '://x', 'not a url at all']) {
      test('"$bad" is rejected', () => expect(() => normalizeServerUrl(bad), throwsFormatException));
    }
  });

  group('platform defaults', () {
    test('the Android emulator reaches the host computer at 10.0.2.2', () => expect(defaultApiUrl(TargetPlatform.android), 'http://10.0.2.2/api/v1'));
    test('the iOS simulator shares the host network', () => expect(defaultApiUrl(TargetPlatform.iOS), 'http://localhost/api/v1'));
    test('desktop uses localhost', () => expect(defaultApiUrl(TargetPlatform.macOS), 'http://localhost/api/v1'));
  });

  group('ServerConfig', () {
    test('starts on the default and applies it to every client', () async {
      final a = _client();
      final b = _client();
      final config = ServerConfig(defaultUrl: 'http://def/api/v1', store: MemoryServerStore(), clients: [a, b]);
      await config.load();
      expect(config.url.value, 'http://def/api/v1');
      expect(a.baseUrl, 'http://def/api/v1');
      expect(b.dio.options.baseUrl, 'http://def/api/v1');
    });

    test('saving a new address updates all clients at once and survives a restart', () async {
      final store = MemoryServerStore();
      final a = _client();
      final b = _client();
      final config = ServerConfig(defaultUrl: 'http://def/api/v1', store: store, clients: [a, b]);
      await config.set('192.168.29.218');
      expect(config.url.value, 'http://192.168.29.218/api/v1');
      expect(a.baseUrl, 'http://192.168.29.218/api/v1');
      expect(b.baseUrl, 'http://192.168.29.218/api/v1');

      final c = _client();
      final restarted = ServerConfig(defaultUrl: 'http://def/api/v1', store: store, clients: [c]);
      await restarted.load();
      expect(c.baseUrl, 'http://192.168.29.218/api/v1');
    });

    test('an invalid address is rejected and nothing changes', () async {
      final store = MemoryServerStore();
      final a = _client('http://keep/api/v1');
      final config = ServerConfig(defaultUrl: 'http://def/api/v1', store: store, clients: [a]);
      await expectLater(config.set('ftp://nope'), throwsFormatException);
      expect(a.baseUrl, 'http://keep/api/v1');
      expect(await store.read(), isNull);
    });

    test('reset returns to the default and forgets the saved address', () async {
      final store = MemoryServerStore();
      final a = _client();
      final config = ServerConfig(defaultUrl: 'http://def/api/v1', store: store, clients: [a]);
      await config.set('10.1.1.1');
      await config.reset();
      expect(config.url.value, 'http://def/api/v1');
      expect(a.baseUrl, 'http://def/api/v1');
      expect(await store.read(), isNull);
    });

    test('a corrupt saved value falls back to the default instead of breaking startup', () async {
      final a = _client();
      final config = ServerConfig(defaultUrl: 'http://def/api/v1', store: MemoryServerStore('ftp://garbage'), clients: [a]);
      await config.load();
      expect(a.baseUrl, 'http://def/api/v1');
    });
  });

  group('connection errors', () {
    test('a failure with no response is flagged, and carries the address that was tried', () {
      final e = ApiException.fromDio(DioException(
        requestOptions: RequestOptions(path: '/auth/customer/login', baseUrl: 'http://10.0.2.2/api/v1'),
        type: DioExceptionType.connectionError,
      ));
      expect(e.isConnectionError, isTrue);
      expect(e.address, 'http://10.0.2.2/api/v1');
    });

    test('a server answer is not a connection error', () {
      final e = ApiException.fromDio(DioException(
        requestOptions: RequestOptions(path: '/x', baseUrl: 'http://h/api/v1'),
        response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: 401, data: {'detail': 'Invalid phone or password'}),
      ));
      expect(e.isConnectionError, isFalse);
      expect(e.message, 'Invalid phone or password');
    });
  });
}
