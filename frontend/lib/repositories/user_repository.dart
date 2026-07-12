import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class UserRepository {
  /// Fetch the currently authenticated user using the stored token.
  ///
  /// Note: [token] is accepted for call-site compatibility, but is no
  /// longer manually attached as a header — ApiService already attaches
  /// the current live token via authHeaders() on every request. Passing
  /// it explicitly here previously risked overriding a fresh token with
  /// a stale one if it had changed between the caller reading it and
  /// this request actually firing.
  Future<User?> getCurrentUser(String token) async {
    try {
      final response = await ApiService.get('auth/me');
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        // ✅ FIX: /auth/me nests the user the same way the login response
        // does — under data.user, not directly under data. The previous
        // `(data['data'] ?? data['user'])` stopped one level too shallow,
        // so User.fromJson() was handed {"user": {...}} instead of the
        // actual user fields, and every field silently parsed to its
        // default (hence "Welcome back, Friend!" even when logged in).
        final userJson = (data['data']?['user'] ??
                data['data'] ??
                data['user']) as Map<String, dynamic>;
        return User.fromJson(userJson);
      } else {
        debugPrint("❌ Invalid response in getCurrentUser: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error fetching current user: $e");
      return null;
    }
  }

  /// Fetch user profile by ID (internally `int`, converted to `String` for API call)
  Future<User?> fetchUserProfile(int userId) async {
    try {
      final response = await ApiService.get('users/${userId.toString()}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final userJson =
            (data is Map<String, dynamic> && data.containsKey('data'))
                ? data['data']
                : data;
        return User.fromJson(userJson);
      } else {
        debugPrint(
          "❌ Failed to load user profile: ${response.statusCode} - ${response.body}",
        );
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error fetching user profile: $e");
      return null;
    }
  }

  /// Update user profile (internally `int`, converted to `String` for API call)
  Future<User?> updateUserProfile(
    int userId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await ApiService.patch(
        'users/${userId.toString()}',
        updates,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final userJson =
            (data is Map<String, dynamic> && data.containsKey('data'))
                ? data['data']
                : data;
        return User.fromJson(userJson);
      } else {
        debugPrint("❌ Failed to update user: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error updating user: $e");
      return null;
    }
  }

  static String getProfilePictureUrl(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) {
      return '${ApiService.baseUrl}/uploads/default-avatar.png';
    }
    final baseUrl = ApiService.baseUrl;
    final normalizedPath = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return '$baseUrl/$normalizedPath';
  }
}
