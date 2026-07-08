import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    // ✅ DO NOT load user data in constructor - load on demand
  }

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;

  static const _userKey = 'current_user';
  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
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
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// ✅ FIXED: Login with proper web storage handling
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
        // ✅ Save user data
        _currentUser = data['data']['user'];
        
        developer.log(
          "🔍 Login: User data received - ID=${_currentUser?['id']}, Username=${_currentUser?['username']}",
          name: "AuthService",
        );

        // ✅ CRITICAL: Save user data to SharedPreferences with verification
        final prefs = await SharedPreferences.getInstance();
        final userJson = json.encode(_currentUser);
        
        developer.log(
          "🔍 Login: Saving user data to SharedPreferences...",
          name: "AuthService",
        );
        developer.log(
          "🔍 Login: userJson = $userJson",
          name: "AuthService",
        );
        
        // ✅ Save the user data
        await prefs.setString(_userKey, userJson);
        
        // ✅ IMMEDIATELY verify it was saved
        final savedUser = prefs.getString(_userKey);
        
        if (savedUser != null) {
          developer.log(
            "✅ Login: User data SAVED successfully!",
            name: "AuthService",
          );
          try {
            final decoded = json.decode(savedUser) as Map;
            developer.log(
              "✅ Login: Saved user ID = ${decoded['id']}",
              name: "AuthService",
            );
          } catch (e) {
            developer.log("⚠️ Login: Saved but couldn't decode: $e", name: "AuthService");
          }
        } else {
          developer.log(
            "❌ Login: FAILED to save user data to SharedPreferences!",
            name: "AuthService",
          );
          // ✅ Try alternative: save as simple string
          try {
            final simpleJson = '{"id":${_currentUser?['id']},"username":"${_currentUser?['username']}"}';
            await prefs.setString(_userKey, simpleJson);
            final retrySaved = prefs.getString(_userKey);
            developer.log(
              "🔍 Login: Alternative save result = ${retrySaved != null}",
              name: "AuthService",
            );
          } catch (e2) {
            developer.log("❌ Login: Alternative save also failed: $e2", name: "AuthService");
          }
        }
        
        // ✅ Force flush SharedPreferences (critical for web)
        await prefs.reload();

        // Save tokens to SECURE storage
        if (data['data']['access_token'] != null) {
          await _saveTokensSecurely(
            data['data']['access_token'],
            data['data']['refresh_token'],
          );
        }

        // Save tokens to ApiService
        developer.log("🔄 Saving tokens to ApiService...", name: "AuthService");
        await ApiService.setTokens(
          data['data']['access_token'],
          data['data']['refresh_token'],
        );
        developer.log("✅ Tokens saved to ApiService", name: "AuthService");

        developer.log(
          "✅ User set in AuthService: ID=${userId}, Username=${username}",
          name: "AuthService",
        );
        
        if (userId == null || userId == 0) {
          developer.log(
            "⚠️ WARNING: User ID is null or 0! User data: $_currentUser",
            name: "AuthService",
          );
        }
        
        // ✅ CRITICAL: Verify everything is saved
        developer.log("🔍 Login: Verifying storage after save...", name: "AuthService");
        await debugAuthState();
        
        // ✅ If still not saved, try fetching from API
        if (_currentUser == null || userId == null || userId == 0) {
          developer.log("🔄 Login: User data not saved, trying to fetch from API...", name: "AuthService");
          await fetchUserFromApi();
        }
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

  /// ✅ FIXED: Save tokens with web compatibility
  Future<void> _saveTokensSecurely(
    String accessToken,
    String refreshToken,
  ) async {
    try {
      // ✅ Save to secure storage
      await _secureStorage.write(key: _tokenKey, value: accessToken);
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);

      // ✅ Also save to SharedPreferences for web compatibility
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);
      
      // ✅ Verify tokens were saved
      final savedToken = prefs.getString(_tokenKey);
      developer.log(
        "✅ Tokens saved to storage: token exists = ${savedToken != null}",
        name: "AuthService",
      );
    } catch (e) {
      developer.log("❌ Error saving tokens securely: $e", name: "AuthService");
      // Fallback to SharedPreferences only
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
  }

  /// Get saved token (with migration from SharedPreferences)
  Future<String?> getToken() async {
    try {
      // 1. Try secure storage first
      String? token = await _secureStorage.read(key: _tokenKey);

      if (token != null && token.isNotEmpty) {
        developer.log(
          "✅ Token retrieved from secure storage (length: ${token.length})",
          name: "AuthService",
        );
        return token;
      }

      // 2. Try SharedPreferences (for migration)
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_tokenKey);

      if (token != null && token.isNotEmpty) {
        developer.log(
          "🔄 Token found in SharedPreferences, migrating to secure storage...",
          name: "AuthService",
        );

        // Migrate to secure storage
        await _secureStorage.write(key: _tokenKey, value: token);

        // Remove from SharedPreferences (optional)
        await prefs.remove(_tokenKey);

        developer.log(
          "✅ Token migrated to secure storage",
          name: "AuthService",
        );
        return token;
      }

      // 3. No token found
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
      // Try secure storage first
      String? token = await _secureStorage.read(key: _refreshTokenKey);

      if (token == null || token.isEmpty) {
        // Fallback to SharedPreferences
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
    final hasUser = _currentUser != null;
    final hasUserId = userId != null && userId != 0;
    
    developer.log(
      "🔐 Auth check: token=${token != null}, user=$hasUser, userId=$hasUserId",
      name: "AuthService",
    );
    
    return token != null && token.isNotEmpty && hasUser && hasUserId;
  }

  /// Get current user ID
  int? get userId {
    if (_currentUser == null) {
      return null;
    }
    
    try {
      final id = _currentUser!['id'];
      
      if (id == null) return null;
      
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
      if (id is double) return id.toInt();
      
      if (id is Map) {
        final idValue = id['id'] ?? id['value'] ?? id['_id'];
        if (idValue is int) return idValue;
        if (idValue is String) return int.tryParse(idValue);
        if (idValue is double) return idValue.toInt();
        return null;
      }
      
      return null;
    } catch (e) {
      developer.log("❌ Error getting user ID: $e", name: "AuthService");
      return null;
    }
  }

  int get userIdOrZero {
    final id = userId;
    return id ?? 0;
  }

  bool get hasValidUserId {
    final id = userId;
    return id != null && id > 0;
  }

  String? get username {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['username'] as String?;
    } catch (e) {
      return null;
    }
  }

  String? get fullName {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['full_name'] as String? ?? 
             _currentUser!['fullName'] as String?;
    } catch (e) {
      return null;
    }
  }

  String? get email {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['email'] as String?;
    } catch (e) {
      return null;
    }
  }

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

  Map<String, dynamic>? getUserData() {
    if (_currentUser == null) return null;
    return Map<String, dynamic>.from(_currentUser!);
  }

  bool hasRole(String role) {
    if (_currentUser == null) return false;
    try {
      final roles = _currentUser!['roles'] as List? ?? [];
      return roles.contains(role);
    } catch (e) {
      return false;
    }
  }

  bool get isAdmin {
    return hasRole('admin') || hasRole('ADMIN');
  }

  /// Logout
  Future<void> logout() async {
    try {
      developer.log("🔄 Starting logout process...", name: "AuthService");
      
      _currentUser = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);

      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _refreshTokenKey);

      await ApiService.clearTokens();

      developer.log("✅ Logout completed - all tokens cleared", name: "AuthService");
    } catch (e) {
      developer.log("❌ Error during logout: $e", name: "AuthService");
    }
  }

  /// ✅ FIXED: Load current user from storage
  Future<void> _loadCurrentUser() async {
    try {
      developer.log("🔍 _loadCurrentUser: Starting...", name: "AuthService");
      
      final prefs = await SharedPreferences.getInstance();
      
      // ✅ DEBUG: Check all stored keys
      final allKeys = prefs.getKeys();
      developer.log("🔍 All SharedPreferences keys: $allKeys", name: "AuthService");
      
      final userJson = prefs.getString(_userKey);
      
      developer.log(
        "🔍 _loadCurrentUser: userJson exists = ${userJson != null}",
        name: "AuthService",
      );
      developer.log(
        "🔍 _loadCurrentUser: userJson length = ${userJson?.length ?? 0}",
        name: "AuthService",
      );
      
      if (userJson != null && userJson.isNotEmpty) {
        developer.log(
          "🔍 _loadCurrentUser: userJson = $userJson",
          name: "AuthService",
        );
        
        try {
          _currentUser = json.decode(userJson) as Map<String, dynamic>;

          developer.log(
            "✅ Loaded user from storage: ID=${_currentUser?['id']}, Username=${_currentUser?['username']}",
            name: "AuthService",
          );
          
          final id = _currentUser?['id'];
          developer.log(
            "🔍 User ID from storage: $id (type: ${id.runtimeType})",
            name: "AuthService",
          );

          final token = await getToken();
          final refreshToken = await getRefreshToken();

          if (token != null && refreshToken != null) {
            await ApiService.setTokens(token, refreshToken);
            developer.log("✅ Tokens loaded into ApiService", name: "AuthService");
          } else {
            developer.log("⚠️ Tokens not found in storage", name: "AuthService");
          }
        } catch (e) {
          developer.log("❌ Error decoding user JSON: $e", name: "AuthService");
          developer.log("❌ JSON string: $userJson", name: "AuthService");
          _currentUser = null;
        }
      } else {
        developer.log("ℹ️ No user found in storage", name: "AuthService");
        
        // ✅ If user data not found but token exists, try to fetch from API
        final token = await getToken();
        if (token != null && token.isNotEmpty) {
          developer.log("🔄 Token exists but no user data. Fetching from API...", name: "AuthService");
          await fetchUserFromApi();
        }
      }
    } catch (e) {
      developer.log("❌ Error loading user from storage: $e", name: "AuthService");
    }
  }

  /// ✅ FIXED: Force refresh user data with more retries
  Future<void> refreshUser({int retries = 5}) async {
    developer.log("🔄 Refreshing user data...", name: "AuthService");
    
    for (int i = 0; i < retries; i++) {
      await _loadCurrentUser();
      
      if (_currentUser != null && userId != null && userId != 0) {
        developer.log(
          "✅ User refreshed successfully: ID=$userId",
          name: "AuthService",
        );
        return;
      }
      
      if (i < retries - 1) {
        developer.log(
          "⏳ User not loaded, retrying (${i + 1}/$retries)...",
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
      
      // ✅ Verify update
      final saved = prefs.getString(_userKey);
      developer.log(
        "✅ User data updated: ${newData.keys} - saved=${saved != null}",
        name: "AuthService",
      );
    } catch (e) {
      developer.log("❌ Error updating user data: $e", name: "AuthService");
    }
  }

  /// ✅ FIXED: Debug method to check authentication state
  Future<void> debugAuthState() async {
    developer.log("🔍 AUTH STATE DEBUG", name: "AuthService");
    developer.log("═" * 50, name: "AuthService");
    
    developer.log("📋 USER INFO:", name: "AuthService");
    developer.log("   - Current User: $_currentUser", name: "AuthService");
    developer.log("   - User ID (getter): $userId", name: "AuthService");
    developer.log("   - User ID (type): ${userId?.runtimeType}", name: "AuthService");
    developer.log("   - Username: $username", name: "AuthService");
    developer.log("   - Full Name: $fullName", name: "AuthService");
    developer.log("   - Email: $email", name: "AuthService");
    developer.log("   - Profile Picture: $profilePicture", name: "AuthService");
    developer.log("   - Has Valid User ID: ${hasValidUserId}", name: "AuthService");
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
    final prefs = await SharedPreferences.getInstance();
    
    final allKeys = prefs.getKeys();
    developer.log("   - All SharedPreferences keys: $allKeys", name: "AuthService");
    
    final spToken = prefs.getString(_tokenKey);
    developer.log("   - SharedPreferences token: ${spToken != null}", name: "AuthService");
    if (spToken != null) {
      developer.log("   - Token length: ${spToken.length}", name: "AuthService");
    }
    
    final spUser = prefs.getString(_userKey);
    developer.log("   - SharedPreferences user: ${spUser != null}", name: "AuthService");
    if (spUser != null) {
      developer.log("   - User data length: ${spUser.length}", name: "AuthService");
      try {
        final userData = json.decode(spUser);
        developer.log("   - User data keys: ${(userData as Map).keys}", name: "AuthService");
        developer.log("   - User ID in storage: ${userData['id']}", name: "AuthService");
        developer.log("   - Username in storage: ${userData['username']}", name: "AuthService");
      } catch (e) {
        developer.log("   - ❌ Failed to parse user data: $e", name: "AuthService");
        developer.log("   - Raw data: $spUser", name: "AuthService");
      }
    }

    final ssToken = await _secureStorage.read(key: _tokenKey);
    developer.log("   - Secure Storage token: ${ssToken != null}", name: "AuthService");
    
    final ssRefresh = await _secureStorage.read(key: _refreshTokenKey);
    developer.log("   - Secure Storage refresh: ${ssRefresh != null}", name: "AuthService");

    developer.log("═" * 50, name: "AuthService");
    developer.log("🔍 END AUTH DEBUG", name: "AuthService");
  }

  /// Clear user data (for testing/debug)
  Future<void> clearUserData() async {
    developer.log("🧹 Clearing user data...", name: "AuthService");
    _currentUser = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    
    await ApiService.clearTokens();
    
    developer.log("✅ User data cleared", name: "AuthService");
  }

  /// ✅ FIXED: Fetch user from API with better error handling
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
        developer.log(
          "🔍 fetchUserFromApi: Response data = $data",
          name: "AuthService",
        );
        
        final user = data['data']?['user'] ?? data['user'] ?? data;
        
        if (user != null && user['id'] != null) {
          _currentUser = user;
          
          // ✅ Save to storage
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_userKey, json.encode(user));
          await prefs.reload();
          
          // ✅ Verify save
          final saved = prefs.getString(_userKey);
          developer.log(
            "✅ User fetched from API: ID=${user['id']} - saved=${saved != null}",
            name: "AuthService",
          );
          return user;
        } else {
          developer.log("⚠️ fetchUserFromApi: No user found in response", name: "AuthService");
        }
      } else {
        developer.log(
          "❌ fetchUserFromApi: Failed with status ${response.statusCode}",
          name: "AuthService",
        );
      }
      return null;
    } catch (e) {
      developer.log("❌ Error fetching user from API: $e", name: "AuthService");
      return null;
    }
  }
}
