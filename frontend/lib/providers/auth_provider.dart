import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart'; // ✅ FIX: needed to hydrate AuthService

/// ✅ Unified UserModel that accepts both int and string IDs
class UserModel {
  final int id;
  final String username;
  final List<String> roles;
  final bool canGoLive;

  UserModel({
    required this.id,
    required this.username,
    required this.roles,
    this.canGoLive = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: _parseId(json['id']),
      username: json['username'] ?? '',
      roles: List<String>.from(json['roles'] ?? []),
      canGoLive: json['can_go_live'] == true,
    );
  }

  bool get isAdmin => roles.contains('admin');

  /// Whether this user should see a "Go Live" option: admins always can,
  /// everyone else needs the can_go_live permission an admin grants (see
  /// LiveBroadcastRepository.setBroadcastPermission).
  bool get canStartBroadcast => isAdmin || canGoLive;

  /// ✅ Safe parser for id (works with both int and string from backend)
  static int _parseId(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    throw ArgumentError("Invalid type for id: ${value.runtimeType}");
  }

  /// ✅ Handy string getter if you need `id` as string
  String get idString => id.toString();
}

class AuthProvider with ChangeNotifier {
  String? _token;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<String?>? _tokenSubscription;

  UserModel? _currentUser; // ✅ holds logged-in user profile

  // Getters
  bool get isAuthenticated => _token != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get token => _token;
  UserModel? get currentUser => _currentUser;
  List<String> get roles => _currentUser?.roles ?? [];

  /// 🔹 Load token from ApiService on app start
  Future<void> loadToken() async {
    await ApiService.init(); // loads saved tokens
    _token = ApiService.authToken;
    notifyListeners();

    // 🔹 Listen for token updates globally
    _tokenSubscription?.cancel();
    _tokenSubscription = ApiService.tokenStream.listen((newToken) {
      _token = newToken;
      notifyListeners();
    });
  }

  /// 🔹 Try automatic login (if tokens exist in storage)
  Future<bool> tryAutoLogin() async {
    await loadToken();

    if (_token == null) {
      debugPrint("⚠️ No saved token, auto-login failed.");
      return false;
    }

    // ✅ fetch profile from backend
    await fetchProfile();

    debugPrint("✅ Auto-login success with saved token.");
    return true;
  }

  /// 🔹 Login method
  Future<bool> login(String identifier, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final baseUrl = dotenv.env['BACKEND_URL'];
      if (baseUrl == null || baseUrl.isEmpty) {
        _error = "❌ BACKEND_URL is not set in .env file";
        return false;
      }

      final response = await ApiService.post('auth/login', {
        'identifier': identifier,
        'password': password,
      });

      debugPrint(
        "⬅️ Login response: ${response.statusCode} - ${response.body}",
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        final access = responseData['data']?['access_token'];
        final refresh = responseData['data']?['refresh_token'];

        // Save + set tokens globally
        await ApiService.setTokens(access, refresh);

        // ✅ Sync from ApiService
        _token = ApiService.authToken;

        // ✅ Build current user from response
        final userJson = responseData['data']?['user'];
        if (userJson != null) {
          _currentUser = UserModel.fromJson(userJson);

          // ✅ FIX: hydrate AuthService immediately so AuthService().userId /
          // getUserId() are populated right away for every login, regardless
          // of whether this device has any prior cached session. This is
          // what was missing — AuthProvider previously never wrote to
          // AuthService's storage/memory, so screens reading from
          // AuthService (e.g. GroupChatDetail, socket join logic) saw null
          // on first-ever logins.
          await AuthService().setUserFromExternal(userJson);
        }

        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = responseData['message'] ?? 'Login failed';
        return false;
      }
    } catch (error) {
      debugPrint("❌ Login error: $error");

      if (error is ApiException) {
        _error = error.message;
      } else {
        _error = 'Failed to connect to the server';
      }

      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 🔹 Register method — mirrors login(): the backend's POST
  /// /auth/register already returns access/refresh tokens and the new
  /// user on success (see backend/api/v1/auth.py), so there's no reason
  /// to make someone who just filled out a whole registration form type
  /// their username and password again on the login screen right after.
  /// This stores those tokens and hydrates the session exactly like
  /// login() does, so the caller can go straight to '/home'.
  Future<bool> register(Map<String, String> fields) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.post('auth/register', fields);
      final responseData = json.decode(response.body);

      final access = responseData['data']?['access_token'];
      final refresh = responseData['data']?['refresh_token'];
      if (access != null && refresh != null) {
        await ApiService.setTokens(access, refresh);
        _token = ApiService.authToken;
      }

      final userJson = responseData['data']?['user'];
      if (userJson != null) {
        _currentUser = UserModel.fromJson(userJson);
        await AuthService().setUserFromExternal(userJson);
      }

      _error = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      // The backend's field-level validation message (e.g. "Password
      // must contain an uppercase letter", "username already exists")
      // lives in error.message — surface it directly.
      _error = error.message;
      return false;
    } catch (error) {
      debugPrint("❌ Registration error: $error");
      _error =
          "Couldn't reach the server. Check your connection and try again.";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 🔹 Fetch user profile from backend using token
  Future<void> fetchProfile() async {
    if (_token == null) return;

    // ✅ Avoid a second /auth/me round trip: main.dart already calls
    // AuthService.refreshUser() before AuthProvider.tryAutoLogin() runs,
    // so on a normal cold start AuthService.currentUser is already
    // populated with the exact same profile this method would otherwise
    // fetch again over the network. Reuse it when present; only hit the
    // API if AuthService genuinely has nothing cached (e.g. this is
    // called standalone, outside the main.dart boot sequence).
    final cached = AuthService().currentUser;
    if (cached != null) {
      _currentUser = UserModel.fromJson(cached);
      notifyListeners();
      return;
    }

    try {
      final response = await ApiService.get("auth/me");
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // ✅ FIX: unwrap consistently with AuthService.fetchUserFromApi(),
        // in case /auth/me nests the user under data.user rather than
        // returning it directly under data.
        final userJson = data['data']?['user'] ?? data['data'] ?? data['user'];

        if (userJson != null) {
          _currentUser = UserModel.fromJson(userJson);

          // ✅ FIX: hydrate AuthService here too. tryAutoLogin() goes
          // through fetchProfile() rather than login(), so without this,
          // app-restart/auto-login sessions would still leave AuthService
          // with a null user even though AuthProvider is authenticated.
          await AuthService().setUserFromExternal(userJson);

          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("⚠️ Failed to fetch profile: $e");
    }
  }

  /// 🔹 Logout method
  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    await ApiService.clearTokens();

    // ✅ FIX: keep AuthService in sync on logout too, otherwise a stale
    // user/id can linger in AuthService after AuthProvider has logged out.
    await AuthService().clearUserData();

    notifyListeners();
  }

  /// 🔹 Role helpers
  bool hasRole(String role) => roles.contains(role);
  bool hasAnyRole(List<String> checkRoles) =>
      roles.any((r) => checkRoles.contains(r));

  @override
  void dispose() {
    _tokenSubscription?.cancel();
    super.dispose();
  }
}
