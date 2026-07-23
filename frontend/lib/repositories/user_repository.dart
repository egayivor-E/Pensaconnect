import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class UserRepository {
  // In-memory, per-session cache of profiles already fetched by id.
  // Lets a profile that's been viewed once re-open instantly (no
  // network round-trip) instead of re-paying the full request latency
  // every time — e.g. tapping the same avatar twice, or backing out of
  // a profile and returning to it. `fetchUserProfile` still refreshes
  // this from the network every call so the cache never goes stale for
  // more than one visit; `cachedUserProfile` is the synchronous,
  // no-await lookup a screen can use to paint instantly on first frame
  // while the real fetch runs in the background.
  static final Map<int, User> _profileCache = {};

  /// Synchronous cache lookup — returns null if this user hasn't been
  /// fetched yet this session. Use to render immediately, then call
  /// [fetchUserProfile] to get (and cache) the current version.
  static User? cachedUserProfile(int userId) => _profileCache[userId];

  // ✅ FIX ("avatar tap loads before opening the profile"): the skeleton
  // spinner in UserProfileScreen only skips itself when
  // `cachedUserProfile` already has something for this id — which was
  // only ever true on a *second* visit, after a full fetchUserProfile()
  // round trip had already happened once. The very first tap on anyone's
  // avatar, anywhere (home feed, chat, live members, wherever), always
  // had nothing cached yet, so it always paid for a full network round
  // trip before showing anything.
  //
  // But by the time someone taps an avatar, the tapped widget almost
  // always already has the name and photo in memory — it's exactly what
  // was used to render that avatar. This lets a caller (see
  // widgets/user_avatar.dart) hand that over right before navigating, so
  // the profile header can paint instantly on the very first tap too.
  // `_load()` still runs underneath immediately after to fetch the real,
  // complete profile — this is only ever a placeholder for the header,
  // never treated as the final source of truth.
  static void seedProfileCache({
    required int userId,
    String? username,
    String? profilePicture,
  }) {
    // Never stomp a real, fully-fetched profile with a thinner
    // placeholder — only fill in the gap when there's nothing cached yet.
    if (_profileCache.containsKey(userId)) return;
    _profileCache[userId] = User(
      id: userId,
      username: (username == null || username.isEmpty) ? 'User' : username,
      email: '',
      profilePicture: profilePicture,
      roles: const [],
    );
  }

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
        final userJson =
            (data['data']?['user'] ?? data['data'] ?? data['user'])
                as Map<String, dynamic>;
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
        final user = User.fromJson(userJson);
        _profileCache[userId] = user;
        return user;
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
        final user = User.fromJson(userJson);
        _profileCache[userId] = user;
        return user;
      } else {
        debugPrint("❌ Failed to update user: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error updating user: $e");
      return null;
    }
  }

  /// Paginated list of users — used by the "New Message" picker to find
  /// someone to start a direct chat with.
  Future<List<User>> listUsers({int page = 1, int perPage = 30}) async {
    try {
      final response = await ApiService.get(
        'users/',
        queryParams: {'page': page, 'per_page': perPage},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final usersJson = (data is Map<String, dynamic> && data['data'] is List)
            ? data['data'] as List
            : (data is List ? data : const []);
        return usersJson
            .map<User>((u) => User.fromJson(u as Map<String, dynamic>))
            .toList();
      } else {
        debugPrint("❌ Failed to list users: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error listing users: $e");
      return [];
    }
  }

  static String getProfilePictureUrl(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) {
      return '${ApiService.baseUrl}/uploads/default-avatar.png';
    }

    // Already an absolute URL (e.g. Supabase storage) — use as-is.
    if (relativePath.startsWith('http://') ||
        relativePath.startsWith('https://')) {
      return relativePath;
    }

    final baseUrl = ApiService.baseUrl;
    final normalizedPath = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return '$baseUrl/$normalizedPath';
  }
}
