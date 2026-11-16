import '../api/api_client.dart';
import '../models/token_pair.dart';

enum UserRole { customer, driver }

class AuthRepository {
  AuthRepository(this._client, this.role);

  final ApiClient _client;
  final UserRole role;

  /// The authenticated HTTP client for this role, for feature-specific API calls.
  ApiClient get client => _client;

  String get _prefix => '/auth/${role.name}';

  Future<void> register(Map<String, dynamic> fields) async {
    final json = await _client.postJson('$_prefix/register', fields);
    await _client.storage.save(TokenPair.fromJson(json));
  }

  /// [identifier] is an email address or a mobile number.
  Future<void> login(String identifier, String password) async {
    final json = await _client.postJson('$_prefix/login', {'identifier': identifier, 'password': password});
    await _client.storage.save(TokenPair.fromJson(json));
  }

  Future<Map<String, dynamic>> me() => _client.getJson('/${role.name}s/me');

  Future<bool> hasSession() async => await _client.storage.read() != null;

  Future<void> logout() => _client.storage.clear();
}
