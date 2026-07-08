import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
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
  static const _userIdKey = 'user_id';
  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  // ✅ Web-safe SecureStorage with proper Android options
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

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

  /// Login with proper, safe storage (cross-platform)
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
        final userData = data['data']['user'];
        final accessToken = data['data']['access_token'];
        final refreshToken = data['data']['refresh_token'];
        final userId = userData['id'].toString();

        _currentUser = userData;

        // ✅ 1. Save sensitive tokens to Secure Storage (Safe on Mobile & Web)
        await _secureStorage.write(key: _tokenKey, value: accessToken);
        await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
        await _secureStorage.write(key: _userIdKey, value: userId);

        // ✅ 2. Save non-sensitive metadata to SharedPreferences
        //    (Automatically uses localStorage on Web!)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, json.encode(userData));
        await prefs.setString(_userIdKey, userId);
        await prefs.reload();

        // ✅ 3. Configure API client
        await ApiService.setTokens(accessToken, refreshToken);

        developer.log(
          "✅ Login successful: User ID=$userId, Username=${userData['username']}",
          name: "AuthService",
        );

        // ✅ Debug verification
        await debugAuthState();
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

  /// Get user ID from storage (async)
  Future<int?> getUserIdFromStorage() async {
    try {
      // 1. Try secure storage first
      String? userId = await _secureStorage.read(key: _userIdKey);
      if (userId != null && userId.isNotEmpty) {
        return int.tryParse(userId);
      }

      // 2. Try SharedPreferences as fallback
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getString(_userIdKey);
      if (userId != null && userId.isNotEmpty) {
        return int.tryParse(userId);
      }

      return null;
    } catch (e) {
      developer.log("❌ Error getting user ID from storage: $e", name: "AuthService");
      return null;
    }
  }

  /// Get saved access token
  Future<String?> getToken() async {
    try {
      // 1. Try secure storage first
      String? token = await _secureStorage.read(key: _tokenKey);
      if (token != null && token.isNotEmpty) {
        return token;
      }

      // 2. Try SharedPreferences as fallback
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_tokenKey);
      return token;
    } catch (e) {
      developer.log("❌ Error retrieving token: $e", name: "AuthService");
      return null;
    }
  }

  /// Get refresh token
  Future<String?> getRefreshToken() async {
    try {
      String? token = await _secureStorage.read(key: _refreshTokenKey);
      if (token != null && token.isNotEmpty) {
        return token;
      }

      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_refreshTokenKey);
      return token;
    } catch (e) {
      developer.log("❌ Error retrieving refresh token: $e", name: "AuthService");
      return null;
    }
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    final userId = await getUserIdFromStorage();
    final hasUser = _currentUser != null;

    developer.log(
      "🔐 Auth check: token=${token != null}, userId=$userId, user=$hasUser",
      name: "AuthService",
    );

    return token != null && token.isNotEmpty && userId != null && userId > 0;
  }

  /// Get current user ID (sync - memory only)
  int? get userId {
    if (_currentUser != null) {
      final id = _currentUser!['id'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
      if (id is double) return id.toInt();
    }
    return null;
  }

  /// Get current username
  String? get username {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['username'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get current full name
  String? get fullName {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['full_name'] as String? ?? 
             _currentUser!['fullName'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get user email
  String? get email {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['email'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get profile picture
  String? get profilePicture {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['profile_picture'] as String? ??
             _currentUser!['profilePicture'] as String? ??
             _currentUser!['avatar'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Check if user has a specific role
  bool hasRole(String role) {
    if (_currentUser == null) return false;
    try {
      final roles = _currentUser!['roles'] as List? ?? [];
      return roles.contains(role);
    } catch (e) {
      return false;
    }
  }

  /// Check if user is admin
  bool get isAdmin {
    return hasRole('admin') || hasRole('ADMIN');
  }

  /// Logout
  Future<void> logout() async {
    try {
      developer.log("🔄 Starting logout process...", name: "AuthService");

      _currentUser = null;

      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      await prefs.remove(_userIdKey);
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);

      // Clear Secure Storage
      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _refreshTokenKey);
      await _secureStorage.delete(key: _userIdKey);

      // Clear ApiService
      await ApiService.clearTokens();

      developer.log("✅ Logout completed", name: "AuthService");
    } catch (e) {
      developer.log("❌ Error during logout: $e", name: "AuthService");
    }
  }

  /// Load current user from storage
  Future<void> _loadCurrentUser() async {
    try {
      developer.log("🔍 _loadCurrentUser: Starting...", name: "AuthService");

      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);

      developer.log(
        "🔍 _loadCurrentUser: userJson exists = ${userJson != null}",
        name: "AuthService",
      );

      if (userJson != null && userJson.isNotEmpty) {
        try {
          _currentUser = json.decode(userJson) as Map<String, dynamic>;

          developer.log(
            "✅ Loaded user from storage: ID=${_currentUser?['id']}, Username=${_currentUser?['username']}",
            name: "AuthService",
          );

          // Load tokens into ApiService
          final token = await getToken();
          final refreshToken = await getRefreshToken();
          if (token != null && refreshToken != null) {
            await ApiService.setTokens(token, refreshToken);
            developer.log("✅ Tokens loaded into ApiService", name: "AuthService");
          }
        } catch (e) {
          developer.log("❌ Error decoding user JSON: $e", name: "AuthService");
          _currentUser = null;
        }
      } else {
        developer.log("ℹ️ No user found in storage", name: "AuthService");
      }
    } catch (e) {
      developer.log("❌ Error loading user from storage: $e", name: "AuthService");
    }
  }

  /// Force refresh user data
  Future<void> refreshUser({int retries = 5}) async {
    developer.log("🔄 Refreshing user data...", name: "AuthService");

    for (int i = 0; i < retries; i++) {
      await _loadCurrentUser();

      final userId = await getUserIdFromStorage();

      if (_currentUser != null || (userId != null && userId > 0)) {
        developer.log(
          "✅ User refreshed: ID=$userId",
          name: "AuthService",
        );
        return;
      }

      if (i < retries - 1) {
        developer.log(
          "⏳ Retrying (${i + 1}/$retries)...",
          name: "AuthService",
        );
        await Future.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    }

    developer.log(
      "⚠️ Failed to refresh user after $retries attempts",
      name: "AuthService",
    );
  }

  /// Update current user data
  Future<void> updateUser(Map<String, dynamic> newData) async {
    if (_currentUser == null) {
      developer.log("❌ Cannot update: No user loaded", name: "AuthService");
      return;
    }

    try {
      _currentUser!.addAll(newData);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, json.encode(_currentUser));
      await prefs.reload();

      developer.log("✅ User data updated: ${newData.keys}", name: "AuthService");
    } catch (e) {
      developer.log("❌ Error updating user data: $e", name: "AuthService");
    }
  }

  /// Debug method to check authentication state
  Future<void> debugAuthState() async {
    developer.log("🔍 AUTH STATE DEBUG", name: "AuthService");
    developer.log("═" * 50, name: "AuthService");

    developer.log("📋 USER INFO:", name: "AuthService");
    developer.log("   - Current User: $_currentUser", name: "AuthService");
    developer.log("   - User ID (memory): $userId", name: "AuthService");
    developer.log("   - Username: $username", name: "AuthService");
    developer.log("   - Full Name: $fullName", name: "AuthService");
    developer.log("   - Email: $email", name: "AuthService");
    developer.log("   - Has Valid User ID: ${userId != null && userId! > 0}", name: "AuthService");
    developer.log("   - Is Admin: ${isAdmin}", name: "AuthService");

    developer.log("🔑 TOKEN INFO:", name: "AuthService");
    final token = await getToken();
    developer.log("   - Token exists: ${token != null}", name: "AuthService");
    developer.log("   - Token length: ${token?.length ?? 0}", name: "AuthService");

    final refreshToken = await getRefreshToken();
    developer.log("   - Refresh Token exists: ${refreshToken != null}", name: "AuthService");

    final isAuth = await isAuthenticated();
    developer.log("   - Is Authenticated: $isAuth", name: "AuthService");

    developer.log("💾 STORAGE CHECK:", name: "AuthService");

    // Check Secure Storage
    final userIdSecure = await _secureStorage.read(key: _userIdKey);
    developer.log("   - Secure Storage user_id: ${userIdSecure != null}", name: "AuthService");
    if (userIdSecure != null) {
      developer.log("   - User ID in secure storage: $userIdSecure", name: "AuthService");
    }

    // Check SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final spUserId = prefs.getString(_userIdKey);
    developer.log("   - SharedPreferences user_id: ${spUserId != null}", name: "AuthService");
    if (spUserId != null) {
      developer.log("   - User ID in SharedPreferences: $spUserId", name: "AuthService");
    }

    final spUser = prefs.getString(_userKey);
    developer.log("   - SharedPreferences user: ${spUser != null}", name: "AuthService");
    if (spUser != null) {
      developer.log("   - User data length: ${spUser.length}", name: "AuthService");
    }

    developer.log("═" * 50, name: "AuthService");
    developer.log("🔍 END AUTH DEBUG", name: "AuthService");
  }

  /// Clear user data (for testing/debug)
  Future<void> clearUserData() async {
    developer.log("🧹 Clearing user data...", name: "AuthService");
    _currentUser = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);

    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _userIdKey);

    await ApiService.clearTokens();

    developer.log("✅ User data cleared", name: "AuthService");
  }

  /// Fetch user from API
  Future<Map<String, dynamic>?> fetchUserFromApi() async {
    try {
      developer.log("🔄 Fetching user from API...", name: "AuthService");

      final response = await ApiService.get('auth/me');

      developer.log(
        "🔍 fetchUserFromApi: Status code = ${response.statusCode}",
        name: "AuthService",
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final user = data['data']?['user'] ?? data['user'] ?? data;

        if (user != null && user['id'] != null) {
          _currentUser = user;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_userKey, json.encode(user));
          await prefs.setString(_userIdKey, user['id'].toString());
          await prefs.reload();

          // Also save to secure storage
          await _secureStorage.write(key: _userIdKey, value: user['id'].toString());

          developer.log(
            "✅ User fetched from API: ID=${user['id']}",
            name: "AuthService",
          );
          return user;
        }
      }
      return null;
    } catch (e) {
      developer.log("❌ Error fetching user from API: $e", name: "AuthService");
      return null;
    }
  }
}
