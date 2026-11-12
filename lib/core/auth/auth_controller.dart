import 'package:get/get.dart';

import '../api/api_exception.dart';
import 'auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthController extends GetxController {
  AuthController(this._repo);

  final AuthRepository _repo;

  final status = AuthStatus.unknown.obs;
  final isLoading = false.obs;
  final error = RxnString();
  final profile = <String, dynamic>{}.obs;

  UserRole get role => _repo.role;

  /// Called on app start: restores a stored session if the server still accepts it.
  Future<void> bootstrap() async {
    try {
      if (!await _repo.hasSession()) {
        status.value = AuthStatus.unauthenticated;
        return;
      }
    } catch (_) {
      // Unreadable secure storage must not leave the app stuck on the splash screen.
      status.value = AuthStatus.unauthenticated;
      return;
    }
    await _loadProfile();
  }

  Future<bool> login(String phone, String password) =>
      _authenticate(() => _repo.login(phone, password));

  Future<bool> register(Map<String, dynamic> fields) =>
      _authenticate(() => _repo.register(fields));

  Future<void> refreshProfile() => _loadProfile();

  Future<void> logout() async {
    await _repo.logout();
    profile.clear();
    status.value = AuthStatus.unauthenticated;
  }

  Future<bool> _authenticate(Future<void> Function() action) async {
    isLoading.value = true;
    error.value = null;
    try {
      await action();
      await _loadProfile();
      return status.value == AuthStatus.authenticated;
    } on ApiException catch (e) {
      error.value = e.message;
      status.value = AuthStatus.unauthenticated;
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadProfile() async {
    try {
      profile.assignAll(await _repo.me());
      status.value = AuthStatus.authenticated;
    } on ApiException catch (e) {
      // A stored token the server rejects (or no network at start) must land on login, not crash.
      if (e.statusCode == 401) await _repo.logout();
      error.value = e.statusCode == 401 ? null : e.message;
      status.value = AuthStatus.unauthenticated;
    }
  }
}
