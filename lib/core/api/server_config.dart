import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import 'api_client.dart';

/// Turns what a person types ("192.168.0.10", "http://host:8000") into the API base URL.
/// Throws [FormatException] when it cannot be an http(s) address.
String normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) {
    throw const FormatException('empty or contains spaces');
  }
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    throw const FormatException('not an http(s) address');
  }
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.isEmpty) path = '/api/v1';
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

/// Where the backend is by default for the platform the app runs on.
/// The Android emulator sees the host computer at 10.0.2.2; the iOS simulator and desktop share its network.
String defaultApiUrl(TargetPlatform platform) =>
    platform == TargetPlatform.android
    ? 'http://10.0.2.2/api/v1'
    : 'http://localhost/api/v1';

abstract class ServerStore {
  Future<String?> read();
  Future<void> save(String url);
  Future<void> clear();
}

class SecureServerStore implements ServerStore {
  SecureServerStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'server_url';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> save(String url) => _storage.write(key: _key, value: url);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryServerStore implements ServerStore {
  MemoryServerStore([this._url]);

  String? _url;

  @override
  Future<String?> read() async => _url;

  @override
  Future<void> save(String url) async => _url = url;

  @override
  Future<void> clear() async => _url = null;
}

/// The backend address the app talks to. One value shared by every API client, remembered across restarts.
class ServerConfig {
  ServerConfig({required this.defaultUrl, required this.store, required this.clients, this.honourSaved = true}) : url = defaultUrl.obs;

  final String defaultUrl;

  /// False when the address was fixed at build time with `--dart-define=API_BASE_URL=...`.
  final bool honourSaved;
  final ServerStore store;
  final List<ApiClient> clients;

  final RxString url;

  /// Decides the address at startup: the saved one if there is a valid one, otherwise the default.
  Future<void> load() async {
    final saved = honourSaved ? await store.read() : null;
    if (saved == null) {
      _apply(defaultUrl);
      return;
    }
    try {
      _apply(normalizeServerUrl(saved));
    } on FormatException {
      await store.clear(); // a corrupt saved value must not break startup
      _apply(defaultUrl);
    }
  }

  Future<void> set(String input) async {
    final normalized = normalizeServerUrl(input);
    await store.save(normalized);
    _apply(normalized);
  }

  Future<void> reset() async {
    await store.clear();
    _apply(defaultUrl);
  }

  void _apply(String value) {
    url.value = value;
    for (final c in clients) {
      c.baseUrl = value;
    }
  }
}
