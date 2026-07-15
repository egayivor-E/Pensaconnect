import 'dart:convert';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:http/http.dart' as http;
import '../models/timeline_post_model.dart';
import '../services/api_service.dart';

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
  static final TimelinePostRepository _instance =
      TimelinePostRepository._internal();
  factory TimelinePostRepository() => _instance;
  TimelinePostRepository._internal();

  final String endpoint = "timeline-posts";

  Future<List<TimelinePost>> fetchUserPosts(int userId) async {
    final res = await ApiService.get("$endpoint/user/$userId");
    final body = json.decode(res.body);
    final data = body is List ? body : body['data'] as List;
    return data.map((json) => TimelinePost.fromJson(json)).toList();
  }

  Future<MediaUploadResult> uploadMedia(XFile file) async {
    final bytes = await file.readAsBytes();
    final res = await ApiService.postMultipart(
      "$endpoint/upload",
      files: [http.MultipartFile.fromBytes("file", bytes, filename: file.name)],
    );
    final body = json.decode(res.body);
    final data = (body is Map<String, dynamic> && body['data'] != null)
        ? body['data'] as Map<String, dynamic>
        : body as Map<String, dynamic>;
    return MediaUploadResult.fromJson(data);
  }

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

  Future<Map<String, dynamic>> toggleLike(int postId) async {
    final res = await ApiService.post(
      "$endpoint/$postId/like",
      {},
    ); // was /react
    final body = json.decode(res.body);
    final data = (body is Map<String, dynamic> && body['data'] != null)
        ? body['data'] as Map<String, dynamic>
        : body as Map<String, dynamic>;
    return data; // {"liked": bool, "like_count": int}  <-- snake_case
  }

  Future<List<TimelineComment>> fetchComments(int postId) async {
    final res = await ApiService.get("$endpoint/$postId/comments");
    final body = json.decode(res.body);
    final data = (body is Map<String, dynamic> && body['data'] is List)
        ? body['data'] as List
        : (body is List ? body : const []);
    return data
        .map((c) => TimelineComment.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<TimelineComment> addComment(int postId, String content) async {
    final res = await ApiService.post("$endpoint/$postId/comments", {
      "content": content,
    });
    if (res.statusCode != 201) {
      throw ApiException(
        statusCode: res.statusCode,
        message: "Failed to add comment",
        details: json.decode(res.body),
      );
    }
    final body = json.decode(res.body);
    final data = (body is Map<String, dynamic> && body['data'] != null)
        ? body['data'] as Map<String, dynamic>
        : body as Map<String, dynamic>;
    return TimelineComment.fromJson(data);
  }

  Future<void> deleteComment(int commentId) async {
    final res = await ApiService.delete("$endpoint/comments/$commentId");
    if (res.statusCode != 200) {
      throw ApiException(
        statusCode: res.statusCode,
        message: "Failed to delete comment",
        details: json.decode(res.body),
      );
    }
  }
}
