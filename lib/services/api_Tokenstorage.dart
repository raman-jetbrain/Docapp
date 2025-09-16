import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  // Save Token
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  // Get Token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Remove Token
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  // Save Base URL
  static Future<void> saveBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
  }

  // Get Base URL
  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('baseUrl');
  }

  // Remove Base URL
  static Future<void> clearBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('baseUrl');
  }
}


class VerificationTokenStorage {
  static const _storage = FlutterSecureStorage();

  // You can reuse the same keys to keep things in sync
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kOtpResponse = 'otp_verification_response'; // full root JSON
  static const _kUserProfile = 'otp_user_profile'; // nested "Response" JSON

  // Token
  static Future<void> setToken(String token) =>
      _storage.write(key: _kAccessToken, value: token);

  static Future<String?> getToken() => _storage.read(key: _kAccessToken);

  static Future<void> setRefreshToken(String token) =>
      _storage.write(key: _kRefreshToken, value: token);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: _kRefreshToken);

  // Full API response (root)
  static Future<void> setOtpVerificationResponse(
      Map<String, dynamic> json) async {
    await _storage.write(key: _kOtpResponse, value: jsonEncode(json));
  }

  static Future<Map<String, dynamic>?> getOtpVerificationResponse() async {
    final raw = await _storage.read(key: _kOtpResponse);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Nested "Response" object (user/company details)
  static Future<void> setUserProfile(Map<String, dynamic> json) async {
    await _storage.write(key: _kUserProfile, value: jsonEncode(json));
  }

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final raw = await _storage.read(key: _kUserProfile);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() => _storage.deleteAll();
}