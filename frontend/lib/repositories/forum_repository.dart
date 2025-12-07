import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:pensaconnect/services/api_service.dart';
import 'package:pensaconnect/services/forum_api.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../config/config.dart';
import '../models/forum_model.dart';
import '../../utils/forum_event_bus.dart'; // Add this import

class ForumRepository {
  final ForumApi _api;
  final String apiBaseUrl;

  ForumRepository({ForumApi? api})
    : _api = api ?? ForumApi(),
      apiBaseUrl = Config.apiBaseUrl.endsWith('/')
          ? Config.apiBaseUrl.substring(0, Config.apiBaseUrl.length - 1)
          : Config.apiBaseUrl;

  /// ---------------- THREADS ----------------
  Future<List<Map<String, dynamic>>> getThreads() => _api.fetchThreads();

  Future<bool> createThread(String title, String description) async {
    final success = await _api.createThread(title, description);
    if (success) {
      // You could add thread creation events here if needed
      debugPrint("✅ Thread created successfully");
    }
    return success;
  }

  Future<void> toggleReaction(int threadId, String type) async {
    final uri = Uri.parse(
      "${Config.apiBaseUrl}/forums/threads/$threadId/react",
    );
    final headers = await ApiService.authHeaders();

    final response = await http.post(
      uri,
      headers: {...headers, "Content-Type": "application/json"},
      body: jsonEncode({"type": type}),
    );

    if (response.statusCode != 200) {
      debugPrint(
        "❌ Failed to toggle $type → ${response.statusCode}: ${response.body}",
      );
      throw Exception("Failed to toggle $type");
    }

    debugPrint("✅ Successfully toggled $type for thread $threadId");
  }

  Future<void> toggleLikeThread(int threadId) =>
      toggleReaction(threadId, "like");
  Future<void> toggleDislikeThread(int threadId) =>
      toggleReaction(threadId, "dislike");

  /// ---------------- POSTS ----------------
  Future<List<ForumPost>> getPosts(int threadId) async {
    final paginatedData = await _api.fetchPosts(threadId);
    final postList = paginatedData['items'] as List<dynamic>;
    return postList.map((p) => ForumPost.fromJson(p)).toList();
  }

  Future<ForumPost> getPost(int postId) async {
    final data = await _api.fetchPost(postId);
    return ForumPost.fromJson(data);
  }

  // In ForumRepository - update createPost method
  Future<bool> createPost({
    required int threadId,
    required String title,
    required String content,
    List<PlatformFile>? attachments,
  }) async {
    final uri = Uri.parse("${Config.apiBaseUrl}/forums/posts");
    final request = http.MultipartRequest("POST", uri);

    request.headers.addAll(await ApiService.authHeaders());
    request.fields["thread_id"] = threadId.toString();
    request.fields["title"] = title;
    request.fields["content"] = content;

    if (attachments != null) {
      for (var i = 0; i < attachments.length; i++) {
        final file = attachments[i];
        if (kIsWeb && file.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              "files",
              file.bytes!,
              filename: file.name,
            ),
          );
        } else if (file.path != null) {
          request.files.add(
            await http.MultipartFile.fromPath(
              "files",
              file.path!,
              filename: file.name,
            ),
          );
        }
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    // FIX: Check for both 200 and 201 status codes
    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint(
        '❌ createPost failed → Status ${response.statusCode}, Body: ${response.body}',
      );
      return false;
    }

    try {
      final responseData = jsonDecode(response.body);
      if (responseData['data'] != null) {
        final newPost = ForumPost.fromJson(responseData['data']);

        // Notify about new post via event bus
        ForumEventBus().notifyPostCreated(threadId, newPost);
        debugPrint('🎉 Post creation event fired for thread $threadId');
      }
    } catch (e) {
      debugPrint('⚠️ Could not parse post creation response: $e');
    }

    debugPrint('✅ Post created successfully for thread $threadId');
    return true;
  }

  Future<void> toggleLike(int postId) async {
    try {
      await _api.toggleLike(postId);
      debugPrint("✅ Like toggled successfully for post $postId");
    } catch (e) {
      debugPrint("❌ Failed to toggle like for post $postId: $e");
      rethrow;
    }
  }

  Future<void> sharePost(int postId) => _api.sharePost(postId);
  Future<void> approvePost(int postId) => _api.approvePost(postId);
  Future<void> deletePost(int postId) => _api.deletePost(postId);

  /// ---------------- COMMENTS ----------------
  Future<List<ForumComment>> getComments(int postId) async {
    final paginatedData = await _api.fetchComments(postId);
    final commentList = paginatedData['items'] as List<dynamic>;
    return commentList.map((c) => ForumComment.fromJson(c)).toList();
  }

  Future<void> addComment({
    required int threadId, // ✅ add threadId
    required int postId,
    required String content,
    List<PlatformFile>? attachments,
  }) async {
    final uri = Uri.parse("${Config.apiBaseUrl}/forums/posts/$postId/comments");
    final request = http.MultipartRequest("POST", uri);
    request.headers.addAll(await ApiService.authHeaders());

    request.fields["content"] = content;

    if (attachments != null) {
      for (var file in attachments) {
        if (kIsWeb && file.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              "files",
              file.bytes!,
              filename: file.name,
            ),
          );
        } else if (file.path != null) {
          request.files.add(
            await http.MultipartFile.fromPath(
              "files",
              file.path!,
              filename: file.name,
            ),
          );
        }
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint(
        '❌ addComment failed → Status ${response.statusCode}, Body: ${response.body}',
      );
      throw Exception(
        "Failed to add comment: ${response.statusCode} ${response.body}",
      );
    }

    try {
      final responseData = jsonDecode(response.body);
      if (responseData['data'] != null) {
        final newComment = ForumComment.fromJson(responseData['data']);

        // ✅ Fixed: threadId is now passed correctly
        notifyCommentManually(threadId, postId, newComment);

        debugPrint(
          '🎉 Comment creation event fired for thread $threadId → post $postId',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Could not parse comment creation response: $e');
    }

    debugPrint('✅ Comment added successfully to post $postId');
  }

  Future<void> deleteComment(int commentId) async {
    try {
      await _api.deleteComment(commentId);
      debugPrint("✅ Comment $commentId deleted successfully");
    } catch (e) {
      debugPrint("❌ Failed to delete comment $commentId: $e");
      rethrow;
    }
  }

  /// ---------------- ATTACHMENTS ----------------
  Future<void> openAttachment(ForumAttachment attachment) async {
    final ok = await launchUrlString(
      attachment.url,
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw Exception("Could not open ${attachment.url}");
  }

  /// ---------------- UTILITY METHODS ----------------

  // Method to manually trigger events (useful for testing)
  void notifyPostManually(int threadId, ForumPost post) {
    ForumEventBus().notifyPostCreated(threadId, post);
  }

  void notifyCommentManually(int threadId, int postId, ForumComment comment) {
    ForumEventBus().notifyCommentCreated(threadId, postId, comment);
  }
}
