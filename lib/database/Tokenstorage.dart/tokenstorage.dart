import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _authTokenKey = 'auth_token';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<void> saveToken(String token) =>
      _storage.write(key: _authTokenKey, value: token);

  static Future<String?> getToken() => _storage.read(key: _authTokenKey);

  static Future<void> clearToken() => _storage.delete(key: _authTokenKey);

  static Future<void> clearAll() async {
    await _storage.delete(key: _authTokenKey);
  }
}