import 'dart:convert';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:http/http.dart' as http;
import '../models/timeline_post_model.dart';
import '../services/api_service.dart';

/// Result of uploading a photo/video via [TimelinePostRepository.uploadMedia].
/// `isVideo` comes back from the server (it decides based on the file
/// extension), so the client never has to guess.
class MediaUploadResult {
  final String url;
  final bool isVideo;

  MediaUploadResult({required this.url, required this.isVideo});

  factory MediaUploadResult.fromJson(Map<String, dynamic> json) {
    return MediaUploadResult(
      url: json['url'] as String,
      isVideo: json['is_video'] == true,
    );
  }
}

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

  /// Upload a photo or video to POST /timeline-posts/upload. The backend
  /// determines is_video from the file extension itself, so we don't
  /// send that flag — we just read it back off the response and hand
  /// it straight to [addPost]. Uses ApiService.postMultipart so this
  /// gets the same auth-header/token-refresh/interceptor handling as
  /// every other call, and _handleResponse already throws ApiException
  /// on a non-2xx, so there's no separate status check needed here.
  Future<MediaUploadResult> uploadMedia(XFile file) async {
    // Read bytes directly off the XFile (works identically on web and
    // native) instead of using MultipartFile.fromPath, which throws
    // "MultipartFile is only supported where dart:io is available" on
    // Flutter Web because dart:io isn't available there.
    final bytes = await file.readAsBytes();
    final res = await ApiService.postMultipart(
      "$endpoint/upload",
      files: [http.MultipartFile.fromBytes("file", bytes, filename: file.name)],
    );
    final body = json.decode(res.body);
    // success_response() wraps the payload under "data".
    final data = (body is Map<String, dynamic> && body['data'] != null)
        ? body['data'] as Map<String, dynamic>
        : body as Map<String, dynamic>;
    return MediaUploadResult.fromJson(data);
  }

  /// Create a new timeline post. Also logs an Activity server-side so it
  /// shows up in the global Recent feed.
  Future<TimelinePost> addPost({
    required String content,
    String? imageUrl,
    bool isVideo = false,
  }) async {
    final res = await ApiService.post("$endpoint/", {
      "content": content,
      if (imageUrl != null) "image_url": imageUrl,
      if (imageUrl != null) "is_video": isVideo,
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
