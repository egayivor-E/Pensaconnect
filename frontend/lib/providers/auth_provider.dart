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

  UserModel({required this.id, required this.username, required this.roles});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: _parseId(json['id']),
      username: json['username'] ?? '',
      roles: List<String>.from(json['roles'] ?? []),
    );
  }

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

  /// 🔹 Fetch user profile from backend using token
  Future<void> fetchProfile() async {
    if (_token == null) return;

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
