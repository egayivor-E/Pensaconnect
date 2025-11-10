import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/user.dart';

class AuthRepository {
  static const String _userKey = 'current_user';

  User? _cachedUser;

  /// 🔹 Login with identifier & password
  Future<Map<String, dynamic>?> login(
    String identifier,
    String password,
  ) async {
    try {
      final response = await ApiService.post('auth/login', {
        'identifier': identifier,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Save tokens globally
        await ApiService.setTokens(
          data['data']['access_token'],
          data['data']['refresh_token'],
        );

        // Parse user if returned
        if (data['data']['user'] != null) {
          final user = User.fromJson(data['data']['user']);
          await _saveUserToStorage(user);
          _cachedUser = user;
        }

        return data['data'];
      } else {
        debugPrint("❌ Login failed: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Login error: $e");
      return null;
    }
  }

  /// 🔹 Logout user (invalidate server + clear local tokens)
  Future<void> logout() async {
    try {
      await ApiService.post('auth/logout', {});
    } catch (e) {
      debugPrint("⚠️ Error logging out (ignored): $e");
    } finally {
      await ApiService.clearTokens();
      await _clearUserFromStorage();
      _cachedUser = null;
    }
  }

  /// 🔹 Get current logged-in user (cached → local → API)
  Future<User?> getCurrentUser() async {
    if (_cachedUser != null) return _cachedUser;

    // Try local storage
    final localUser = await _loadUserFromStorage();
    if (localUser != null) {
      _cachedUser = localUser;
      return localUser;
    }

    // Fallback: fetch from API
    try {
      final response = await ApiService.get('auth/me');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final user = User.fromJson(data['data']);
        await _saveUserToStorage(user);
        _cachedUser = user;
        return user;
      } else {
        debugPrint(
          "❌ Failed to fetch current user: ${response.statusCode} - ${response.body}",
        );
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error fetching current user: $e");
      return null;
    }
  }

  /// 🔹 Helper: Get current user ID
  Future<int?> getCurrentUserId() async {
    final user = await getCurrentUser();
    return user?.id;
  }

  /// 🔹 Return stored **access token**
  Future<String?> getAccessToken() async {
    return ApiService.authToken;
  }

  /// 🔹 Return stored **refresh token**
  Future<Future<void> Function({int retry})> getRefreshToken() async {
    return ApiService.refreshToken;
  }

  // -------------------------
  // 🔹 Persistence Helpers
  // -------------------------

  Future<void> _saveUserToStorage(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, json.encode(user.toJson()));
  }

  Future<User?> _loadUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson == null) return null;
    try {
      return User.fromJson(json.decode(userJson));
    } catch (e) {
      debugPrint("⚠️ Failed to parse stored user: $e");
      return null;
    }
  }

  Future<void> _clearUserFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }
}
