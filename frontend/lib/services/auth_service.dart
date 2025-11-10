import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    _loadCurrentUser();
  }

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;

  static const _userKey = 'current_user';
  static const _tokenKey = 'access_token';
  static const _secureStorage = FlutterSecureStorage();

  /// Register a new user
  Future<Map<String, dynamic>> register(
    String username,
    String email,
    String password,
  ) async {
    final payload = {
      "username": username,
      "email": email,
      "password": password,
    };

    developer.log(
      "Register Payload: ${json.encode(payload)}",
      name: "AuthService",
    );

    final response = await ApiService.post("auth/register", payload);

    developer.log("Register Response: ${response.body}", name: "AuthService");

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Login with either username OR email
  /// Login with either username OR email
  /// Login with either username OR email
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    final payload = {"identifier": identifier, "password": password};

    developer.log(
      "Login Payload: ${json.encode(payload)}",
      name: "AuthService",
    );

    final response = await ApiService.post("auth/login", payload);
    final data = json.decode(response.body) as Map<String, dynamic>;

    developer.log(
      "Login Response Status: ${data['status']}",
      name: "AuthService",
    );
    developer.log(
      "Has access_token: ${data['data']?['access_token'] != null}",
      name: "AuthService",
    );
    developer.log(
      "Has refresh_token: ${data['data']?['refresh_token'] != null}",
      name: "AuthService",
    );

    if (data['status'] == 'success' && data['data']?['user'] != null) {
      _currentUser = data['data']['user'];

      // Save user info and token locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, json.encode(_currentUser));

      if (data['data']['access_token'] != null) {
        await prefs.setString(_tokenKey, data['data']['access_token']);

        // ✅ CRITICAL: Save tokens to ApiService
        developer.log("🔄 Saving tokens to ApiService...", name: "AuthService");

        await ApiService.setTokens(
          data['data']['access_token'],
          data['data']['refresh_token'],
        );

        developer.log("✅ Tokens saved to ApiService", name: "AuthService");

        // DEBUG: Verify tokens were saved
        await ApiService.debugTokenStatus();
      }
    }

    return data;
  }

  // lib/services/auth_service.dart (Assuming _secureStorage is defined)

  /// Get saved token (if needed for API requests),
  /// migrating from SharedPreferences if found there.
  Future<String?> getToken() async {
    // 1. Check the SECURE storage first (our current, preferred location)
    String? secureToken = await _secureStorage.read(key: _tokenKey);

    if (secureToken != null) {
      // Found it securely. Done.
      return secureToken;
    }

    // 2. If not found, check the OLD INSECURE storage (SharedPreferences)
    final prefs = await SharedPreferences.getInstance();
    String? oldToken = prefs.getString(_tokenKey);

    if (oldToken != null) {
      // 🚨 TOKEN MIGRATION: Token found in the old location!
      developer.log(
        "🔑 Token found in SharedPreferences! Migrating to SecureStorage...",
        name: "AuthService",
      );

      // a) Save the token to the secure storage
      await _secureStorage.write(key: _tokenKey, value: oldToken);

      // b) DELETE the token from the old, insecure storage
      await prefs.remove(_tokenKey);

      developer.log("✅ Token migrated successfully.", name: "AuthService");

      // Return the token for immediate use
      return oldToken;
    }

    // 3. Token not found anywhere
    return null;
  }

  /// Logout
  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await _secureStorage.delete(key: _tokenKey);
    await prefs.remove(_tokenKey);
    // ✅ FIX: Also clear tokens from ApiService
    await ApiService.clearTokens();
  }

  /// Load current user from storage on app start
  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      _currentUser = json.decode(userJson) as Map<String, dynamic>;

      // ✅ FIX: If user exists in SharedPreferences, ensure tokens are loaded in ApiService
      final token = prefs.getString(_tokenKey);
      if (token != null) {
        // This will ensure ApiService has the token from secure storage
        await ApiService.init();
      }
    }
  }
}
