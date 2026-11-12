import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/token_pair.dart';

abstract class TokenStorage {
  Future<void> save(TokenPair tokens);
  Future<TokenPair?> read();
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({String namespace = 'ride', FlutterSecureStorage? storage})
      : _access = '${namespace}_access',
        _refresh = '${namespace}_refresh',
        _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final String _access;
  final String _refresh;

  @override
  Future<void> save(TokenPair tokens) async {
    await _storage.write(key: _access, value: tokens.accessToken);
    await _storage.write(key: _refresh, value: tokens.refreshToken);
  }

  @override
  Future<TokenPair?> read() async {
    final access = await _storage.read(key: _access);
    final refresh = await _storage.read(key: _refresh);
    if (access == null || refresh == null) return null;
    return TokenPair(accessToken: access, refreshToken: refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
  }
}

class MemoryTokenStorage implements TokenStorage {
  TokenPair? _tokens;

  @override
  Future<void> save(TokenPair tokens) async => _tokens = tokens;

  @override
  Future<TokenPair?> read() async => _tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
