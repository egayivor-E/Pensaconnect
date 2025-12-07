import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pensaconnect/services/api_service.dart';
import '../models/worship_song.dart';

class SongService {
  static const Duration timeout = Duration(seconds: 30);

  /// Load all worship songs from API
  static Future<List<WorshipSong>> loadSongs() async {
    try {
      final response = await ApiService.get("worship-songs/");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['status'] == 'success') {
          final List<dynamic> songsData = data['data'];
          return songsData.map((json) => WorshipSong.fromJson(json)).toList();
        } else {
          throw Exception(data['message'] ?? 'Failed to load songs');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: Failed to load songs');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Load songs by category
  static Future<List<WorshipSong>> loadSongsByCategory(int category) async {
    try {
      final response = await ApiService.get(
        "worship-songs/",
        queryParams: {'category': category},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['status'] == 'success') {
          final List<dynamic> songsData = data['data'];
          return songsData.map((json) => WorshipSong.fromJson(json)).toList();
        } else {
          throw Exception(data['message'] ?? 'Failed to load category songs');
        }
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: Failed to load category songs',
        );
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Search songs by query
  static Future<List<WorshipSong>> searchSongs(String query) async {
    try {
      final response = await ApiService.get(
        "worship-songs/search",
        queryParams: {'q': query},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['status'] == 'success') {
          final List<dynamic> songsData = data['data'];
          return songsData.map((json) => WorshipSong.fromJson(json)).toList();
        } else {
          throw Exception(data['message'] ?? 'Search failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: Search failed');
      }
    } catch (e) {
      throw Exception('Search error: $e');
    }
  }

  /// Add YouTube song
  static Future<void> addYouTubeSong(Map<String, dynamic> songData) async {
    try {
      final response = await ApiService.post("worship-songs/youtube", songData);

      final Map<String, dynamic> responseData = json.decode(response.body);

      if (response.statusCode == 201 && responseData['status'] == 'success') {
        return;
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to upload YouTube song',
        );
      }
    } catch (e) {
      throw Exception('Upload error: $e');
    }
  }

  /// Upload audio file for mobile (uses file path)
  static Future<void> uploadAudioFile({
    required String filePath,
    required Map<String, dynamic> songData,
  }) async {
    try {
      if (kIsWeb) {
        throw Exception('Use uploadAudioFileWeb for web platform');
      }

      // Upload audio file
      final uploadResponse = await ApiService.postMultipart(
        "worship-uploads/upload-audio",
        files: [await http.MultipartFile.fromPath('file', filePath)],
      );

      final uploadData = json.decode(uploadResponse.body);

      if (uploadResponse.statusCode == 200 &&
          uploadData['status'] == 'success') {
        // Create song record
        final fileUrl = uploadData['data']['fileUrl'];
        final fileSize = uploadData['data']['fileSize'];

        songData['audioUrl'] = fileUrl;
        songData['fileSize'] = fileSize;
        songData['thumbnailUrl'] =
            songData['thumbnailUrl'] ?? 'assets/images/worship_icon.jpeg';

        final createResponse = await ApiService.post(
          "worship-songs/audio",
          songData,
        );

        final Map<String, dynamic> createData = json.decode(
          createResponse.body,
        );

        if (createResponse.statusCode == 201 &&
            createData['status'] == 'success') {
          return;
        } else {
          throw Exception(
            createData['message'] ?? 'Failed to create audio song',
          );
        }
      } else {
        throw Exception(uploadData['message'] ?? 'Audio file upload failed');
      }
    } catch (e) {
      throw Exception('Audio upload error: $e');
    }
  }

  /// Upload audio file for web (uses file bytes)
  static Future<void> uploadAudioFileWeb({
    required Uint8List fileBytes,
    required String fileName,
    required Map<String, dynamic> songData,
  }) async {
    try {
      // Upload audio file bytes
      final uploadResponse = await ApiService.postMultipart(
        "worship-uploads/upload-audio",
        files: [
          http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
        ],
      );

      final uploadData = json.decode(uploadResponse.body);

      if (uploadResponse.statusCode == 200 &&
          uploadData['status'] == 'success') {
        // Create song record
        final fileUrl = uploadData['data']['fileUrl'];
        final fileSize = uploadData['data']['fileSize'];

        songData['audioUrl'] = fileUrl;
        songData['fileSize'] = fileSize;
        songData['thumbnailUrl'] =
            songData['thumbnailUrl'] ?? 'assets/images/worship_icon.jpeg';

        final createResponse = await ApiService.post(
          "worship-songs/audio",
          songData,
        );

        final Map<String, dynamic> createData = json.decode(
          createResponse.body,
        );

        if (createResponse.statusCode == 201 &&
            createData['status'] == 'success') {
          return;
        } else {
          throw Exception(
            createData['message'] ?? 'Failed to create audio song',
          );
        }
      } else {
        throw Exception(uploadData['message'] ?? 'Audio file upload failed');
      }
    } catch (e) {
      throw Exception('Audio upload error: $e');
    }
  }

  /// Upload video file for mobile (uses file path)
  static Future<void> uploadVideoFile({
    required String filePath,
    required Map<String, dynamic> songData,
  }) async {
    try {
      if (kIsWeb) {
        throw Exception('Use uploadVideoFileWeb for web platform');
      }

      // Upload video file
      final uploadResponse = await ApiService.postMultipart(
        "worship-uploads/upload-video",
        files: [await http.MultipartFile.fromPath('file', filePath)],
      );

      final uploadData = json.decode(uploadResponse.body);

      if (uploadResponse.statusCode == 200 &&
          uploadData['status'] == 'success') {
        // Create song record
        final fileUrl = uploadData['data']['fileUrl'];
        final fileSize = uploadData['data']['fileSize'];

        songData['videoUrl'] = fileUrl;
        songData['fileSize'] = fileSize;
        songData['thumbnailUrl'] =
            songData['thumbnailUrl'] ?? 'assets/images/worship_icon.jpeg';

        final createResponse = await ApiService.post(
          "worship-songs/video",
          songData,
        );

        final Map<String, dynamic> createData = json.decode(
          createResponse.body,
        );

        if (createResponse.statusCode == 201 &&
            createData['status'] == 'success') {
          return;
        } else {
          throw Exception(
            createData['message'] ?? 'Failed to create video song',
          );
        }
      } else {
        throw Exception(uploadData['message'] ?? 'Video file upload failed');
      }
    } catch (e) {
      throw Exception('Video upload error: $e');
    }
  }

  /// Upload video file for web (uses file bytes)
  static Future<void> uploadVideoFileWeb({
    required Uint8List fileBytes,
    required String fileName,
    required Map<String, dynamic> songData,
  }) async {
    try {
      // Upload video file bytes
      final uploadResponse = await ApiService.postMultipart(
        "worship-uploads/upload-video",
        files: [
          http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
        ],
      );

      final uploadData = json.decode(uploadResponse.body);

      if (uploadResponse.statusCode == 200 &&
          uploadData['status'] == 'success') {
        // Create song record
        final fileUrl = uploadData['data']['fileUrl'];
        final fileSize = uploadData['data']['fileSize'];

        songData['videoUrl'] = fileUrl;
        songData['fileSize'] = fileSize;
        songData['thumbnailUrl'] =
            songData['thumbnailUrl'] ?? 'assets/images/worship_icon.jpeg';

        final createResponse = await ApiService.post(
          "worship-songs/video",
          songData,
        );

        final Map<String, dynamic> createData = json.decode(
          createResponse.body,
        );

        if (createResponse.statusCode == 201 &&
            createData['status'] == 'success') {
          return;
        } else {
          throw Exception(
            createData['message'] ?? 'Failed to create video song',
          );
        }
      } else {
        throw Exception(uploadData['message'] ?? 'Video file upload failed');
      }
    } catch (e) {
      throw Exception('Video upload error: $e');
    }
  }

  /// Get specific song
  static Future<WorshipSong> getSong(String songId) async {
    try {
      final response = await ApiService.get("worship-songs/$songId");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['status'] == 'success') {
          return WorshipSong.fromJson(data['data']);
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch song');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Song not found');
      } else {
        throw Exception('HTTP ${response.statusCode}: Failed to fetch song');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Delete song
  static Future<void> deleteSong(String songId) async {
    try {
      final response = await ApiService.delete("worship-songs/$songId");

      final Map<String, dynamic> responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return;
      } else {
        throw Exception(responseData['message'] ?? 'Delete failed');
      }
    } catch (e) {
      throw Exception('Delete error: $e');
    }
  }

  /// Update song metadata
  static Future<void> updateSong(
    String songId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await ApiService.put("worship-songs/$songId", updates);

      final Map<String, dynamic> responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return;
      } else {
        throw Exception(responseData['message'] ?? 'Update failed');
      }
    } catch (e) {
      throw Exception('Update error: $e');
    }
  }

  /// Increment download count
  static Future<void> incrementDownloadCount(String songId) async {
    try {
      final response = await ApiService.post(
        "worship-uploads/download/$songId",
        {},
      );

      final Map<String, dynamic> responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return;
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to increment download count',
        );
      }
    } catch (e) {
      throw Exception('Download count error: $e');
    }
  }

  /// Get song statistics
  static Future<Map<String, dynamic>> getSongStats() async {
    try {
      final response = await ApiService.get("worship-songs/stats");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['status'] == 'success') {
          return data['data'];
        } else {
          throw Exception(data['message'] ?? 'Failed to get stats');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: Failed to get stats');
      }
    } catch (e) {
      throw Exception('Stats error: $e');
    }
  }
}
