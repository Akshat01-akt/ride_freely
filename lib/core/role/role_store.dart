import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_repository.dart';

/// Remembers which interface (customer or driver) this device last used.
abstract class RoleStore {
  Future<UserRole?> read();
  Future<void> save(UserRole role);
  Future<void> clear();
}

class SecureRoleStore implements RoleStore {
  SecureRoleStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ride_role';
  final FlutterSecureStorage _storage;

  @override
  Future<UserRole?> read() async {
    final v = await _storage.read(key: _key);
    return UserRole.values.where((r) => r.name == v).firstOrNull;
  }

  @override
  Future<void> save(UserRole role) => _storage.write(key: _key, value: role.name);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryRoleStore implements RoleStore {
  MemoryRoleStore([this._role]);

  UserRole? _role;

  @override
  Future<UserRole?> read() async => _role;

  @override
  Future<void> save(UserRole role) async => _role = role;

  @override
  Future<void> clear() async => _role = null;
}
