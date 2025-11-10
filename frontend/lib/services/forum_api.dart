import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../../config/config.dart';

class ForumApi {
  // 1. Correct the base URL for Multipart requests: Use the full base API URL.
  // The specific '/forums' path will be added in the multipart request's path.
  final String apiBaseUrl = Config.apiBaseUrl.endsWith('/')
      ? Config.apiBaseUrl.substring(0, Config.apiBaseUrl.length - 1)
      : Config.apiBaseUrl;

  // ---------- THREADS ----------
  Future<List<Map<String, dynamic>>> fetchThreads() async {
    // These calls rely on ApiService to correctly join the path
    final res = await ApiService.get("forums/threads");
    final body = json.decode(res.body);
    return List<Map<String, dynamic>>.from(body['data']);
  }

  Future<bool> createThread(String title, String description) async {
    final res = await ApiService.post("forums/threads", {
      "title": title,
      "description": description,
    });
    return res.statusCode == 201;
  }

  // ---------- POSTS ----------
  Future<Map<String, dynamic>> fetchPosts(int threadId) async {
    final res = await ApiService.get("forums/posts?thread_id=$threadId");
    final body = json.decode(res.body);
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchPost(int postId) async {
    final res = await ApiService.get("forums/posts/$postId");
    final body = json.decode(res.body);
    return body['data'] as Map<String, dynamic>;
  }

  Future<bool> createPost({
    required int threadId,
    required String title,
    required String content,
    List<File>? attachments,
  }) async {
    var uri = Uri.parse("$apiBaseUrl/forums/posts");
    var request = http.MultipartRequest("POST", uri);

    // 1. Add headers and fields
    request.headers.addAll(await ApiService.authHeaders());
    request.fields["thread_id"] = threadId.toString();
    request.fields["title"] = title;
    request.fields["content"] = content;

    // 2. Correctly handle multiple attachments with indexed field names
    if (attachments != null) {
      for (var i = 0; i < attachments.length; i++) {
        var file = attachments[i];
        request.files.add(
          await http.MultipartFile.fromPath(
            "attachments[$i]", // Key fix: Indexed field name
            file.path,
            filename: file.path.split('/').last,
          ),
        );
      }
    }

    // 3. Send the request and await the full response body
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(
      streamedResponse,
    ); // Await the full body

    // 4. Check status code and optionally log error
    if (response.statusCode != 201) {
      // OPTIONAL: Add logging here to see the server's error message
      print(
        'API Error for createPost: Status ${response.statusCode}, Body: ${response.body}',
      );
      // You could also throw an exception here if you want to force the calling screen's catch block
    }

    return response.statusCode == 201; // Return true only on 201 (Created)
  }

  Future<void> toggleLike(int postId) async {
    await ApiService.post("forums/posts/$postId/like", {});
  }

  Future<void> sharePost(int postId) async {
    await ApiService.post("forums/posts/$postId/share", {});
  }

  Future<void> approvePost(int postId) async {
    await ApiService.post("forums/posts/$postId/approve", {});
  }

  Future<void> deletePost(int postId) async {
    await ApiService.delete("forums/posts/$postId");
  }

  // ---------- COMMENTS ----------
  Future<Map<String, dynamic>> fetchComments(int postId) async {
    final res = await ApiService.get("forums/posts/$postId/comments");
    final body = json.decode(res.body);
    return body['data'] as Map<String, dynamic>;
  }

  Future<void> createComment(
    int postId,
    String content, {
    List<File>? attachments,
  }) async {
    var uri = Uri.parse("$apiBaseUrl/forums/posts/$postId/comments");
    var request = http.MultipartRequest("POST", uri);

    request.headers.addAll(await ApiService.authHeaders());
    request.fields["content"] = content;

    if (attachments != null) {
      for (var i = 0; i < attachments.length; i++) {
        // <-- Loop with index
        var file = attachments[i];
        // FIX: Use indexed field name
        request.files.add(
          await http.MultipartFile.fromPath(
            "attachments[$i]", // <-- FIXED: Use indexed field name
            file.path,
            filename: file.path.split('/').last, // Use the actual filename
          ),
        );
      }
    }

    final response = await request.send(); // <-- Await the request.send()
    final finalResponse = await http.Response.fromStream(
      response,
    ); // <-- Get the final response

    // ADDED: Throw an exception if the status code is not 201 (Created)
    if (finalResponse.statusCode != 201) {
      // This allows the calling screen's try/catch block to show the error.
      throw Exception(
        'Failed to create comment. Status: ${finalResponse.statusCode}. Body: ${finalResponse.body}',
      );
    }
  }

  Future<void> deleteComment(int commentId) async {
    await ApiService.delete("forums/comments/$commentId");
  }
}
