import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;

  static const _userKey = 'current_user';
  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _secureStorage = FlutterSecureStorage();

  // ✅ FIXED: Initialize properly
  static Future<AuthService> init() async {
    final instance = AuthService._instance;
    await instance._loadCurrentUser();
    return instance;
  }

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
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Login with either username OR email
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    try {
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

      if (data['status'] == 'success' && data['data']?['user'] != null) {
        // Save user data
        _currentUser = data['data']['user'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, json.encode(_currentUser));

        // Save tokens to SECURE storage
        if (data['data']['access_token'] != null) {
          await _saveTokensSecurely(
            data['data']['access_token'],
            data['data']['refresh_token'],
          );
        }

        // ✅ CRITICAL: Save tokens to ApiService
        developer.log("🔄 Saving tokens to ApiService...", name: "AuthService");
        await ApiService.setTokens(
          data['data']['access_token'],
          data['data']['refresh_token'],
        );
        developer.log("✅ Tokens saved to ApiService", name: "AuthService");

        developer.log(
          "✅ User set in AuthService: ID=${_currentUser?['id']}, Username=${_currentUser?['username']}",
          name: "AuthService",
        );
      } else {
        developer.log(
          "❌ Login failed or missing user data",
          name: "AuthService",
        );
      }

      return data;
    } catch (e, stackTrace) {
      developer.log("❌ Login error: $e\n$stackTrace", name: "AuthService");
      rethrow;
    }
  }

  /// Save tokens securely to FlutterSecureStorage
  Future<void> _saveTokensSecurely(
    String accessToken,
    String refreshToken,
  ) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: accessToken);
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);

      developer.log("✅ Tokens saved to secure storage", name: "AuthService");
    } catch (e) {
      developer.log("❌ Error saving tokens securely: $e", name: "AuthService");
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
  }

  /// Get saved token
  Future<String?> getToken() async {
    try {
      String? token = await _secureStorage.read(key: _tokenKey);

      if (token != null && token.isNotEmpty) {
        developer.log(
          "✅ Token retrieved from secure storage (length: ${token.length})",
          name: "AuthService",
        );
        return token;
      }

      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_tokenKey);

      if (token != null && token.isNotEmpty) {
        developer.log(
          "🔄 Token found in SharedPreferences, migrating to secure storage...",
          name: "AuthService",
        );
        await _secureStorage.write(key: _tokenKey, value: token);
        await prefs.remove(_tokenKey);
        developer.log("✅ Token migrated to secure storage", name: "AuthService");
        return token;
      }

      developer.log("❌ No token found in any storage", name: "AuthService");
      return null;
    } catch (e) {
      developer.log("❌ Error retrieving token: $e", name: "AuthService");
      return null;
    }
  }

  /// Get refresh token
  Future<String?> getRefreshToken() async {
    try {
      String? token = await _secureStorage.read(key: _refreshTokenKey);

      if (token == null || token.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        token = prefs.getString(_refreshTokenKey);
      }

      return token;
    } catch (e) {
      developer.log(
        "❌ Error retrieving refresh token: $e",
        name: "AuthService",
      );
      return null;
    }
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Get current user ID
  int? get userId {
    if (_currentUser == null) return null;
    final id = _currentUser!['id'];
    if (id is int) return id;
    if (id is String) return int.tryParse(id);
    return null;
  }

  /// Get current username
  String? get username {
    if (_currentUser == null) return null;
    return _currentUser!['username'] as String?;
  }

  /// Get current full name
  String? get fullName {
    if (_currentUser == null) return null;
    return _currentUser!['full_name'] as String?;
  }

  /// Logout
  Future<void> logout() async {
    try {
      _currentUser = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);

      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _refreshTokenKey);

      await ApiService.clearTokens();

      developer.log(
        "✅ Logout completed - all tokens cleared",
        name: "AuthService",
      );
    } catch (e) {
      developer.log("❌ Error during logout: $e", name: "AuthService");
    }
  }

  /// Load current user from storage
  Future<void> _loadCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);

      if (userJson != null && userJson.isNotEmpty) {
        _currentUser = json.decode(userJson) as Map<String, dynamic>;

        developer.log(
          "✅ Loaded user from storage: ID=${_currentUser?['id']}, Username=${_currentUser?['username']}",
          name: "AuthService",
        );

        final token = await getToken();
        final refreshToken = await getRefreshToken();

        if (token != null && refreshToken != null) {
          await ApiService.setTokens(token, refreshToken);
          developer.log(
            "✅ Tokens loaded into ApiService from storage",
            name: "AuthService",
          );
        }
      } else {
        developer.log("ℹ️ No user found in storage", name: "AuthService");
      }
    } catch (e) {
      developer.log(
        "❌ Error loading user from storage: $e",
        name: "AuthService",
      );
    }
  }

  // ✅ FIXED: Ensure user is loaded before accessing
  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (_currentUser == null) {
      await _loadCurrentUser();
    }
    return _currentUser;
  }

  // ✅ FIXED: Get user ID with proper loading
  Future<int?> getUserId() async {
    await getCurrentUser();
    return userId;
  }

  /// Debug method to check authentication state
  Future<void> debugAuthState() async {
    developer.log("🔍 AUTH STATE DEBUG", name: "AuthService");
    await getCurrentUser();
    developer.log("   - Current User: $_currentUser", name: "AuthService");
    developer.log("   - User ID: $userId", name: "AuthService");
    developer.log("   - Username: $username", name: "AuthService");

    final token = await getToken();
    developer.log("   - Token exists: ${token != null}", name: "AuthService");
    developer.log(
      "   - Token length: ${token?.length ?? 0}",
      name: "AuthService",
    );

    final isAuth = await isAuthenticated();
    developer.log("   - Is Authenticated: $isAuth", name: "AuthService");

    final prefs = await SharedPreferences.getInstance();
    final spToken = prefs.getString(_tokenKey);
    developer.log(
      "   - SharedPreferences token: ${spToken != null}",
      name: "AuthService",
    );

    final ssToken = await _secureStorage.read(key: _tokenKey);
    developer.log(
      "   - Secure Storage token: ${ssToken != null}",
      name: "AuthService",
    );
  }

  /// Force refresh user data from storage
  Future<void> refreshUser() async {
    await _loadCurrentUser();
  }

  /// Update current user data
  Future<void> updateUser(Map<String, dynamic> newData) async {
    if (_currentUser == null) return;

    _currentUser!.addAll(newData);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, json.encode(_currentUser));

    developer.log("✅ User data updated: ${newData.keys}", name: "AuthService");
  }
}
