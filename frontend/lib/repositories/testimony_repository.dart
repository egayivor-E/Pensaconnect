import 'dart:convert';
import '../models/testimony_model.dart';
import '../services/api_service.dart';

class TestimonyRepository {
  // Singleton pattern
  static final TestimonyRepository _instance = TestimonyRepository._internal();
  factory TestimonyRepository() => _instance;
  TestimonyRepository._internal();

  final String endpoint = "testimonies";

  // Cache management
  final List<Testimony> _cachedTestimonies = [];
  DateTime? _lastFetchTime;
  static const Duration cacheDuration = Duration(minutes: 5);

  /// Get all testimonies with cache support
  Future<List<Testimony>> fetchTestimonies({bool forceRefresh = false}) async {
    // Return cached data if it's fresh and not forcing refresh
    if (!forceRefresh &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheDuration &&
        _cachedTestimonies.isNotEmpty) {
      return List.from(_cachedTestimonies);
    }

    // Fetch from API
    final res = await ApiService.get("$endpoint/");
    final body = json.decode(res.body);

    final data = body is List ? body : body['data'] as List;
    final testimonies = data.map((json) => Testimony.fromJson(json)).toList();

    // Update cache
    _cachedTestimonies.clear();
    _cachedTestimonies.addAll(testimonies);
    _lastFetchTime = DateTime.now();

    return List.from(_cachedTestimonies);
  }

  /// Get a single testimony by ID - tries cache first
  Future<Testimony> fetchTestimony(int id) async {
    // Try to get from cache first for immediate response
    final cachedTestimony = getTestimonyFromCache(id);

    if (cachedTestimony != null) {
      return cachedTestimony;
    }

    // If not in cache, fetch from API
    final res = await ApiService.get("$endpoint/$id");
    final body = json.decode(res.body);

    return body is Map<String, dynamic>
        ? Testimony.fromJson(body)
        : Testimony.fromJson(body['data']);
  }

  /// Create a new testimony and invalidate cache
  Future<void> addTestimony(Map<String, dynamic> data) async {
    final res = await ApiService.post("$endpoint/", data);
    if (res.statusCode != 201) {
      throw ApiException(
        statusCode: res.statusCode,
        message: "Failed to add testimony",
        details: json.decode(res.body),
      );
    }
    // Invalidate cache since we added new data
    _invalidateCache();
  }

  /// Delete testimony and update cache
  Future<void> deleteTestimony(int testimonyId) async {
    final res = await ApiService.delete("$endpoint/$testimonyId");
    if (res.statusCode != 200) {
      throw ApiException(
        statusCode: res.statusCode,
        message: "Failed to delete testimony",
        details: json.decode(res.body),
      );
    }
    // Remove from cache immediately
    _cachedTestimonies.removeWhere((t) => int.parse(t.id) == testimonyId);
  }

  /// Toggle like with immediate cache update
  Future<void> toggleLike(int testimonyId) async {
    // Update cache optimistically
    _updateLikeInCache(testimonyId);

    // Then call API
    final res = await ApiService.post("$endpoint/$testimonyId/like", {});
    if (res.statusCode != 200 && res.statusCode != 201) {
      // If API fails, revert cache change
      _updateLikeInCache(testimonyId); // Toggle back
      throw ApiException(
        statusCode: res.statusCode,
        message: "Failed to toggle like",
        details: json.decode(res.body),
      );
    }
  }

  /// Helper method to update like in cache
  void _updateLikeInCache(int testimonyId) {
    final index = _cachedTestimonies.indexWhere(
      (t) => int.parse(t.id) == testimonyId,
    );
    if (index != -1) {
      final testimony = _cachedTestimonies[index];
      _cachedTestimonies[index] = testimony.copyWith(
        likesCount: testimony.likedByMe
            ? testimony.likesCount - 1
            : testimony.likesCount + 1,
        likedByMe: !testimony.likedByMe,
      );
    }
  }

  /// Helper method to update comment count in cache
  void _updateCommentCountInCache(int testimonyId, {bool increment = true}) {
    final index = _cachedTestimonies.indexWhere(
      (t) => int.parse(t.id) == testimonyId,
    );
    if (index != -1) {
      final testimony = _cachedTestimonies[index];
      _cachedTestimonies[index] = testimony.copyWith(
        commentsCount: increment
            ? testimony.commentsCount + 1
            : testimony.commentsCount - 1,
      );
    }
  }

  /// Get testimony from cache by ID (for immediate access)
  Testimony? getTestimonyFromCache(int id) {
    try {
      return _cachedTestimonies.firstWhere((t) => int.parse(t.id) == id);
    } catch (e) {
      return null;
    }
  }

  /// Invalidate cache
  void _invalidateCache() {
    _lastFetchTime = null;
    _cachedTestimonies.clear();
  }

  /// Fetch comments for a testimony
  Future<List<TestimonyComment>> fetchComments(int testimonyId) async {
    final res = await ApiService.get("$endpoint/$testimonyId/comments");
    final body = json.decode(res.body);

    final data = body is List ? body : body['data'] as List;
    return data.map((json) => TestimonyComment.fromJson(json)).toList();
  }

  /// Add a comment with cache update
  Future<void> addComment(int testimonyId, Map<String, dynamic> data) async {
    // Update cache optimistically
    _updateCommentCountInCache(testimonyId, increment: true);

    try {
      final res = await ApiService.post(
        "$endpoint/$testimonyId/comments",
        data,
      );
      if (res.statusCode != 201) {
        // Rollback on error
        _updateCommentCountInCache(testimonyId, increment: false);
        throw ApiException(
          statusCode: res.statusCode,
          message: "Failed to add comment",
          details: json.decode(res.body),
        );
      }
    } catch (e) {
      // Rollback on network error
      _updateCommentCountInCache(testimonyId, increment: false);
      rethrow;
    }
  }

  Future<int> countUserTestimonies(String userId) async {
    final res = await ApiService.get("$endpoint/?user_id=$userId");
    final body = json.decode(res.body);

    final data = body is List ? body : body['data'] as List;
    return data.length;
  }
}
