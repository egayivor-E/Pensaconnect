import 'dart:convert';
import '../models/timeline_post_model.dart';
import '../services/api_service.dart';

class TimelinePostRepository {
  // Singleton pattern, same as TestimonyRepository
  static final TimelinePostRepository _instance =
      TimelinePostRepository._internal();
  factory TimelinePostRepository() => _instance;
  TimelinePostRepository._internal();

  final String endpoint = "timeline-posts";

  /// Fetch all timeline posts for a given user (their profile feed).
  Future<List<TimelinePost>> fetchUserPosts(int userId) async {
    final res = await ApiService.get("$endpoint/user/$userId");
    final body = json.decode(res.body);
    final data = body is List ? body : body['data'] as List;
    return data.map((json) => TimelinePost.fromJson(json)).toList();
  }

  /// Create a new timeline post. Also logs an Activity server-side so it
  /// shows up in the global Recent feed.
  Future<TimelinePost> addPost({
    required String content,
    String? imageUrl,
  }) async {
    final res = await ApiService.post("$endpoint/", {
      "content": content,
      if (imageUrl != null) "image_url": imageUrl,
    });
    if (res.statusCode != 201) {
      throw ApiException(
        statusCode: res.statusCode,
        message: "Failed to create post",
        details: json.decode(res.body),
      );
    }
    final body = json.decode(res.body);
    return TimelinePost.fromJson(
      body is Map<String, dynamic> ? body : body['data'],
    );
  }

  /// Delete a post. The backend also removes the matching Activity row,
  /// so this deletes the post from the profile AND the Recent feed.
  Future<void> deletePost(int postId) async {
    final res = await ApiService.delete("$endpoint/$postId");
    if (res.statusCode != 200) {
      throw ApiException(
        statusCode: res.statusCode,
        message: "Failed to delete post",
        details: json.decode(res.body),
      );
    }
  }
}
