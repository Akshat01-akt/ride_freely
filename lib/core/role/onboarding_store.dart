import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers whether the intro slides have been shown on this device.
abstract class OnboardingStore {
  Future<bool> isDone();
  Future<void> markDone();
}

class SecureOnboardingStore implements OnboardingStore {
  SecureOnboardingStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'onboarding_done';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> isDone() async => await _storage.read(key: _key) == '1';

  @override
  Future<void> markDone() => _storage.write(key: _key, value: '1');
}

class MemoryOnboardingStore implements OnboardingStore {
  MemoryOnboardingStore([this._done = true]);

  bool _done;

  @override
  Future<bool> isDone() async => _done;

  @override
  Future<void> markDone() async => _done = true;
}
