import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/worship_song.dart';
import './api_service.dart'; // Assuming you have an ApiService
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  final Map<String, String> _localPaths = {};

  // Getters for progress tracking
  double getDownloadProgress(String songId) => _downloadProgress[songId] ?? 0.0;
  bool isDownloading(String songId) => _isDownloading[songId] ?? false;

  /// Check and request storage permission
  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        final result = await Permission.storage.request();
        return result.isGranted;
      }
      return true;
    } else if (Platform.isIOS) {
      final status = await Permission.photosAddOnly.status; // For iOS
      if (!status.isGranted) {
        final result = await Permission.photosAddOnly.request();
        return result.isGranted;
      }
      return true;
    }
    return true;
  }

  /// Get downloads directory
  Future<Directory> getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      return Directory('${directory?.path}/PensaConnect/Downloads');
    } else {
      final directory = await getApplicationDocumentsDirectory();
      return Directory('${directory.path}/PensaConnect/Downloads');
    }
  }

  /// MAIN FIX: Use backend download endpoint instead of direct URL
  Future<String?> downloadSong(WorshipSong song) async {
    // Check if song is downloadable
    if (!song.allowDownload) {
      throw Exception('This song is not available for download');
    }

    if (!await _checkStoragePermission()) {
      throw Exception('Storage permission denied');
    }

    final songId = song.id.toString();
    _isDownloading[songId] = true;
    _downloadProgress[songId] = 0.0;

    try {
      // Create downloads directory
      final dir = await getDownloadsDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Create file path
      final fileExtension = song.isAudio ? 'mp3' : 'mp4';
      final fileName = '${song.id}_${song.title}_${song.artist}.$fileExtension'
          .replaceAll(RegExp(r'[^\w\s.-]'), '_')
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'_+'), '_');
      final filePath = '${dir.path}/$fileName';

      // NEW: Use backend download endpoint
      final downloadUrl =
          '${ApiService.baseUrl}/api/v1/worship-songs/${song.id}/download';

      // Get auth token
      final token = await _getAuthToken();

      // Create request with auth header
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = '*/*';

      // Send request and track progress
      final client = http.Client();
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'Download failed with status: ${streamedResponse.statusCode}',
        );
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      int bytesReceived = 0;

      final file = File(filePath);
      final sink = file.openWrite();

      await streamedResponse.stream
          .listen(
            (List<int> chunk) {
              bytesReceived += chunk.length;
              sink.add(chunk);

              if (contentLength > 0) {
                final progress = bytesReceived / contentLength;
                _downloadProgress[songId] = progress;
              }
            },
            onDone: () async {
              await sink.flush();
              await sink.close();

              _downloadProgress.remove(songId);
              _isDownloading.remove(songId);
              _localPaths[songId] = filePath;

              print('Download complete: $filePath');
            },
            onError: (error) async {
              await sink.close();
              if (await file.exists()) {
                await file.delete(); // Clean up partial file
              }
              _downloadProgress.remove(songId);
              _isDownloading.remove(songId);
              throw Exception('Download error: $error');
            },
            cancelOnError: true,
          )
          .asFuture();

      client.close();
      return filePath;
    } catch (e) {
      _downloadProgress.remove(songId);
      _isDownloading.remove(songId);
      rethrow;
    }
  }

  /// Download with progress tracking (Updated for backend endpoint)
  Future<String?> downloadSongWithProgress(
    WorshipSong song, {
    required Function(double progress) onProgress,
    required Function(String? filePath) onComplete,
    required Function(String error) onError,
  }) async {
    final songId = song.id.toString();

    // Check if song is downloadable
    if (!song.allowDownload) {
      onError('This song is not available for download');
      return null;
    }

    try {
      if (!await _checkStoragePermission()) {
        onError('Storage permission denied');
        return null;
      }

      final dir = await getDownloadsDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final fileExtension = song.isAudio ? 'mp3' : 'mp4';
      final fileName = '${song.id}_${song.title}_${song.artist}.$fileExtension'
          .replaceAll(RegExp(r'[^\w\s.-]'), '_')
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'_+'), '_');
      final filePath = '${dir.path}/$fileName';

      // Use backend download endpoint
      final downloadUrl =
          '${ApiService.baseUrl}/api/v1/worship-songs/${song.id}/download';
      final token = await _getAuthToken();

      _isDownloading[songId] = true;

      final request = http.Request('GET', Uri.parse(downloadUrl));
      // request.headers['Authorization'] = 'Bearer $token';
      // request.headers['Accept'] = '*/*';

      final client = http.Client();
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        onError('Download failed: ${streamedResponse.statusCode}');
        _isDownloading.remove(songId);
        return null;
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      int bytesReceived = 0;

      final file = File(filePath);
      final sink = file.openWrite();

      await streamedResponse.stream
          .listen(
            (List<int> chunk) {
              bytesReceived += chunk.length;
              sink.add(chunk);

              if (contentLength > 0) {
                final progress = bytesReceived / contentLength;
                _downloadProgress[songId] = progress;
                onProgress(progress);
              }
            },
            onDone: () async {
              await sink.flush();
              await sink.close();
              client.close();

              _isDownloading.remove(songId);
              _downloadProgress.remove(songId);
              _localPaths[songId] = filePath;

              onComplete(filePath);
            },
            onError: (error) async {
              await sink.close();
              client.close();

              if (await file.exists()) {
                await file.delete();
              }

              _isDownloading.remove(songId);
              _downloadProgress.remove(songId);
              onError('Download error: $error');
            },
            cancelOnError: true,
          )
          .asFuture();

      return filePath;
    } catch (e) {
      _isDownloading.remove(songId);
      _downloadProgress.remove(songId);
      onError('Download error: $e');
      return null;
    }
  }

  // In download_service.dart, add to DownloadService class:
  Future<int> getTotalDownloadSize(List<WorshipSong> allSongs) async {
    try {
      int totalBytes = 0;
      final downloadedSongs = await getDownloadedSongs(allSongs);

      for (final song in downloadedSongs) {
        // Check if WorshipSong has fileSize property
        // You might need to adjust this based on your actual model
        if (song.fileSize != null) {
          totalBytes += song.fileSize!;
        } else {
          // If no fileSize property, check the actual file
          final filePath = await getLocalFilePath(song);
          if (filePath != null) {
            final file = File(filePath);
            if (await file.exists()) {
              totalBytes += await file.length();
            }
          }
        }
      }

      return totalBytes;
    } catch (e) {
      print('Error calculating total download size: $e');
      return 0;
    }
  }

  /// Web-specific download using browser's download manager
  Future<void> _downloadForWeb(
    WorshipSong song,
    Function(double progress) onProgress,
    Function(String? filePath) onComplete,
    Function(String error) onError,
  ) async {
    try {
      // For web, trigger browser download
      final downloadUrl =
          '${ApiService.baseUrl}/api/v1/worship-songs/${song.id}/download';

      print('🌐 Web download URL: $downloadUrl');

      // Create anchor element
      final anchor = html.AnchorElement(href: downloadUrl)
        ..target = '_blank'
        ..download =
            '${song.title}_${song.artist}.${song.isAudio ? 'mp3' : 'mp4'}'
        ..style.display = 'none';

      // Add to document
      html.document.body?.children.add(anchor);

      // Simulate progress for UI
      onProgress(0.1);
      await Future.delayed(Duration(milliseconds: 300));
      onProgress(0.5);
      await Future.delayed(Duration(milliseconds: 300));
      onProgress(1.0);

      // Trigger download
      anchor.click();

      // Clean up
      html.document.body?.children.remove(anchor);

      // Complete
      onComplete('web_download_started');

      print('✅ Web download triggered successfully');
    } catch (e) {
      print('❌ Web download error: $e');
      onError('Web download failed: $e');
      rethrow;
    }
  }

  /// Helper method to get auth token
  Future<String> _getAuthToken() async {
    // Implement based on your auth system
    // Example using shared_preferences:
    // final prefs = await SharedPreferences.getInstance();
    // return prefs.getString('auth_token') ?? '';

    // For testing, you might return a hardcoded token
    // return 'YOUR_TEST_TOKEN';

    // Or get from your AuthProvider
    // return Provider.of<AuthProvider>(context, listen: false).token;

    throw Exception('Implement _getAuthToken() method');
  }

  /// Check if song is downloaded
  Future<bool> isSongDownloaded(WorshipSong song) async {
    final songId = song.id.toString();

    // Check our local paths cache first
    if (_localPaths.containsKey(songId)) {
      final file = File(_localPaths[songId]!);
      return await file.exists();
    }

    // Fallback to searching in directory
    final localPath = await getLocalFilePath(song);
    if (localPath != null) {
      _localPaths[songId] = localPath;
      return true;
    }

    return false;
  }

  /// Get local file path for song
  Future<String?> getLocalFilePath(WorshipSong song) async {
    final songId = song.id.toString();

    // Check cache first
    if (_localPaths.containsKey(songId)) {
      final cachedPath = _localPaths[songId]!;
      final file = File(cachedPath);
      if (await file.exists()) {
        return cachedPath;
      } else {
        _localPaths.remove(songId);
      }
    }

    // Search in directory
    try {
      final dir = await getDownloadsDirectory();
      if (await dir.exists()) {
        final files = await dir.list().toList();

        for (final file in files) {
          if (file is File) {
            final fileName = file.uri.pathSegments.last;
            // Match by song ID (most reliable)
            if (fileName.startsWith('${song.id}_')) {
              _localPaths[songId] = file.path;
              return file.path;
            }
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Delete downloaded song
  Future<bool> deleteDownloadedSong(WorshipSong song) async {
    try {
      final filePath = await getLocalFilePath(song);
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          _localPaths.remove(song.id.toString());
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get all downloaded songs
  Future<List<WorshipSong>> getDownloadedSongs(
    List<WorshipSong> allSongs,
  ) async {
    final downloadedSongs = <WorshipSong>[];

    for (final song in allSongs) {
      if (await isSongDownloaded(song)) {
        downloadedSongs.add(song);
      }
    }

    return downloadedSongs;
  }

  /// Cancel ongoing download
  void cancelDownload(String songId) {
    _isDownloading.remove(songId);
    _downloadProgress.remove(songId);
  }

  /// Clear all downloads
  Future<void> clearAllDownloads() async {
    try {
      final dir = await getDownloadsDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _localPaths.clear();
    } catch (e) {
      throw Exception('Failed to clear downloads: $e');
    }
  }

  /// Get download statistics
  Future<Map<String, dynamic>> getDownloadStats(
    List<WorshipSong> allSongs,
  ) async {
    final downloadedSongs = await getDownloadedSongs(allSongs);
    int totalSize = 0;

    for (final song in downloadedSongs) {
      final filePath = await getLocalFilePath(song);
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          totalSize += await file.length();
        }
      }
    }

    return {
      'downloadedCount': downloadedSongs.length,
      'totalSize': totalSize,
      'totalSizeFormatted': _formatBytes(totalSize),
      'downloadedSongs': downloadedSongs,
    };
  }

  /// Format bytes to human readable string
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
