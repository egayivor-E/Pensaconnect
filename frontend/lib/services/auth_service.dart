import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // ==================== STATE ====================
  Map<String, dynamic>? _currentUser;
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _lastError;

  // ==================== GETTERS ====================
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  /// Get user ID synchronously (checks memory first)
  int? get userId {
    if (_currentUser != null) {
      final id = _currentUser!['id'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
      if (id is double) return id.toInt();
    }
    return null;
  }

  /// Get username synchronously
  String? get username {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['username'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get full name synchronously
  String? get fullName {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['full_name'] as String? ??
             _currentUser!['fullName'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get email synchronously
  String? get email {
    if (_currentUser == null) return null;
    try {
      return _currentUser!['email'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Get profile picture synchronously
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
  bool get isAdmin => hasRole('admin') || hasRole('ADMIN');

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

  // ==================== STORAGE KEYS ====================
  static const _userKey = 'current_user';
  static const _userIdKey = 'user_id';
  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  // ==================== STORAGE ====================
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ==================== INITIALIZATION ====================
  /// Initialize the auth service - MUST be called at app startup
  Future<void> initialize() async {
    if (_isInitialized) {
      developer.log("ℹ️ AuthService already initialized", name: "AuthService");
      return;
    }

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      developer.log("🚀 Initializing AuthService...", name: "AuthService");
      await _loadCurrentUser();
      _isInitialized = true;

      developer.log(
        "✅ AuthService initialized: User ID = $userId, User = ${_currentUser != null}",
        name: "AuthService",
      );

      await debugAuthState();
    } catch (e) {
      _lastError = e.toString();
      developer.log("❌ AuthService initialization error: $e", name: "AuthService");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ==================== AUTH METHODS ====================
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
    _isLoading = true;
    _lastError = null;
    notifyListeners();

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

        // Set in memory
        _currentUser = userData;

        // Save to all storage locations
        await _saveUserData(userData, accessToken, refreshToken, userId);

        // Configure API client
        await ApiService.setTokens(accessToken, refreshToken);

        developer.log(
          "✅ Login successful: User ID=$userId, Username=${userData['username']}",
          name: "AuthService",
        );

        _isInitialized = true;
        notifyListeners();

        await debugAuthState();
      } else {
        _lastError = "Login failed: ${data['message'] ?? 'Unknown error'}";
        developer.log(
          "❌ Login failed: ${_lastError}",
          name: "AuthService",
        );
      }

      return data;
    } catch (e, stackTrace) {
      _lastError = e.toString();
      developer.log("❌ Login error: $e\n$stackTrace", name: "AuthService");
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      developer.log("🔄 Starting logout process...", name: "AuthService");

      _currentUser = null;
      _isInitialized = false;

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

      notifyListeners();
      developer.log("✅ Logout completed", name: "AuthService");
    } catch (e) {
      developer.log("❌ Error during logout: $e", name: "AuthService");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh user data
  Future<void> refreshUser({int retries = 5}) async {
    developer.log("🔄 Refreshing user data...", name: "AuthService");

    // Nothing to refresh for a logged-out device: retrying auth/me here
    // just burns ~3s of exponential-backoff delay (300+600+900+1200ms)
    // plus 5 doomed network round trips on every cold start, since a
    // missing token can never become valid by waiting. Bail out fast so
    // guests reach the app immediately.
    final token = await getToken();
    if (token == null || token.isEmpty) {
      developer.log(
        "ℹ️ No stored token — skipping refresh retries (guest session)",
        name: "AuthService",
      );
      _isInitialized = true;
      notifyListeners();
      return;
    }

    for (int i = 0; i < retries; i++) {
      await _loadCurrentUser();

      // Also try to fetch from API if storage is empty
      if (_currentUser == null) {
        await fetchUserFromApi();
      }

      final userId = await getUserIdFromStorage();
      final hasValidUser = _currentUser != null || (userId != null && userId > 0);

      if (hasValidUser) {
        developer.log(
          "✅ User refreshed: ID=$userId",
          name: "AuthService",
        );
        _isInitialized = true;
        notifyListeners();
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

  // ==================== USER DATA MANAGEMENT ====================
  /// Save user data to all storage locations
  Future<void> _saveUserData(
    Map<String, dynamic> userData,
    String accessToken,
    String refreshToken,
    String userId,
  ) async {
    try {
      // Save to Secure Storage
      await _secureStorage.write(key: _tokenKey, value: accessToken);
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
      await _secureStorage.write(key: _userIdKey, value: userId);

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, json.encode(userData));
      await prefs.setString(_userIdKey, userId);
      await prefs.reload();

      developer.log("✅ User data saved to all storage locations", name: "AuthService");
    } catch (e) {
      developer.log("❌ Error saving user data: $e", name: "AuthService");
      rethrow;
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

          _isInitialized = true;
          notifyListeners();
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

  /// Get user ID from storage (async)
  Future<int?> getUserIdFromStorage() async {
    try {
      // 1. Check memory first (fastest)
      if (_currentUser != null) {
        final id = _currentUser!['id'];
        if (id is int) return id;
        if (id is String) return int.tryParse(id);
        if (id is double) return id.toInt();
      }

      // 2. Try secure storage
      String? userId = await _secureStorage.read(key: _userIdKey);
      if (userId != null && userId.isNotEmpty) {
        return int.tryParse(userId);
      }

      // 3. Try SharedPreferences as fallback
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

  /// Get user ID asynchronously (comprehensive)
  Future<int?> getUserId() async {
    // Check memory first
    if (_currentUser != null) {
      final id = _currentUser!['id'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
      if (id is double) return id.toInt();
    }

    // Fall back to storage
    return await getUserIdFromStorage();
  }

  /// Get saved access token
  ///
  /// ✅ FIX: AuthService used to read the access token exclusively from its
  /// own `FlutterSecureStorage` instance, which is configured with different
  /// Android options (`encryptedSharedPreferences: true`) than ApiService's
  /// storage instance. On Android these can be backed by physically
  /// different stores, so writes to one are invisible to the other even
  /// though both use the same key name ('access_token').
  ///
  /// In practice this meant: login wrote the token into AuthService's
  /// storage, but every subsequent background refresh (ApiService.
  /// refreshToken() → setTokens()) only ever updated ApiService's copy.
  /// AuthService's copy — the one SocketIoService reads via
  /// AuthService().getToken() — was frozen at its login-time value forever.
  /// After the access token's ~1hr lifetime expired, any WebSocket
  /// (re)connect would keep sending that same dead token and fail with
  /// "Signature has expired", no matter how many times ApiService had
  /// silently refreshed it in the background.
  ///
  /// ApiService is the only component that actually performs refreshes, so
  /// it must be the single source of truth. We defer to its live,
  /// in-memory token first, and only fall back to our own storage for the
  /// brief cold-start window before ApiService has initialized.
  Future<String?> getToken() async {
    try {
      final apiToken = await ApiService.getToken();
      if (apiToken != null && apiToken.isNotEmpty) {
        return apiToken;
      }

      // Fallback: ApiService hasn't been hydrated yet (e.g. very first
      // read at cold start, before _loadCurrentUser() has run).
      String? token = await _secureStorage.read(key: _tokenKey);
      if (token != null && token.isNotEmpty) {
        return token;
      }

      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_tokenKey);
      return token;
    } catch (e) {
      developer.log("❌ Error retrieving token: $e", name: "AuthService");
      return null;
    }
  }

  /// Get refresh token
  ///
  /// ✅ FIX: same storage split-brain as getToken() above — defer to
  /// ApiService's live refresh token instead of our own, possibly-stale,
  /// separately-stored copy.
  Future<String?> getRefreshToken() async {
    try {
      await ApiService.ensureInitialized();
      final apiRefreshToken = ApiService.refreshTokenValue;
      if (apiRefreshToken != null && apiRefreshToken.isNotEmpty) {
        return apiRefreshToken;
      }

      // Fallback for the same cold-start window as getToken() above.
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

          _isInitialized = true;
          notifyListeners();
          return user;
        }
      }
      return null;
    } catch (e) {
      developer.log("❌ Error fetching user from API: $e", name: "AuthService");
      return null;
    }
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
      notifyListeners();
    } catch (e) {
      developer.log("❌ Error updating user data: $e", name: "AuthService");
    }
  }

  /// ✅ NEW: Hydrate AuthService with user data obtained by another auth
  /// flow (e.g. AuthProvider.tryAutoLogin / login), so both stay in sync.
  /// This fixes the bug where AuthProvider has a valid session but
  /// AuthService.currentUser / getUserId() stay null because AuthProvider
  /// never writes to AuthService's storage keys.
  Future<void> setUserFromExternal(Map<String, dynamic> userData) async {
    try {
      _currentUser = userData;
      _isInitialized = true;

      final id = userData['id'];
      if (id != null) {
        final idStr = id.toString();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, json.encode(userData));
        await prefs.setString(_userIdKey, idStr);
        await prefs.reload();

        await _secureStorage.write(key: _userIdKey, value: idStr);
      }

      developer.log(
        "✅ AuthService hydrated externally: ID=${userData['id']}",
        name: "AuthService",
      );
      notifyListeners();
    } catch (e) {
      developer.log("❌ Error in setUserFromExternal: $e", name: "AuthService");
    }
  }

  /// Clear user data (for testing/debug)
  Future<void> clearUserData() async {
    developer.log("🧹 Clearing user data...", name: "AuthService");
    _currentUser = null;
    _isInitialized = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);

    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _userIdKey);

    await ApiService.clearTokens();

    notifyListeners();
    developer.log("✅ User data cleared", name: "AuthService");
  }

  // ==================== WAIT FOR INITIALIZATION ====================
  /// Wait for AuthService to be initialized
  Future<void> waitForInitialization({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isInitialized) return;

    final completer = Completer<void>();
    bool resolved = false;

    void listener() {
      if (_isInitialized && !resolved) {
        resolved = true;
        completer.complete();
      }
    }

    addListener(listener);

    try {
      await completer.future.timeout(timeout, onTimeout: () {
        if (!resolved) {
          resolved = true;
          developer.log("⏰ Timeout waiting for AuthService initialization", name: "AuthService");
          // Try to initialize
          initialize();
        }
      });
    } finally {
      removeListener(listener);
    }
  }

  // ==================== DEBUG ====================
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
    developer.log("   - Is Initialized: $_isInitialized", name: "AuthService");

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
}