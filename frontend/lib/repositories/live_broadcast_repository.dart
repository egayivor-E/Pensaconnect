// lib/repositories/live_broadcast_repository.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// YouTube's own tri-state for a video, as returned by its Data API's
/// `liveBroadcastContent` field — this is the real source of truth for
/// whether a broadcast is actually live, as opposed to just "a video ID
/// is configured" (which is all the app previously had access to).
enum YoutubeBroadcastStatus {
  live,
  upcoming,
  none,
  // The backend couldn't determine status — either it hasn't been given
  // a YOUTUBE_API_KEY yet, or the request itself failed (network error,
  // not logged in, etc). Kept distinct from `none` deliberately: `none`
  // is a confident "this isn't a live broadcast", `unknown` is "we
  // genuinely don't know", and callers should treat them differently
  // (unknown degrades to the old assume-it's-fine behavior rather than
  // claiming the stream definitely isn't live).
  unknown,
  notFound,
}

class YoutubeBroadcastInfo {
  final YoutubeBroadcastStatus status;
  final int? concurrentViewers;
  final DateTime? scheduledStartTime;

  const YoutubeBroadcastInfo({
    required this.status,
    this.concurrentViewers,
    this.scheduledStartTime,
  });

  factory YoutubeBroadcastInfo.unknown() =>
      const YoutubeBroadcastInfo(status: YoutubeBroadcastStatus.unknown);

  factory YoutubeBroadcastInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['broadcast_status'] as String?;
    final status = switch (raw) {
      'live' => YoutubeBroadcastStatus.live,
      'upcoming' => YoutubeBroadcastStatus.upcoming,
      'none' => YoutubeBroadcastStatus.none,
      'not_found' => YoutubeBroadcastStatus.notFound,
      _ => YoutubeBroadcastStatus.unknown,
    };
    return YoutubeBroadcastInfo(
      status: status,
      concurrentViewers: json['concurrent_viewers'] is int
          ? json['concurrent_viewers'] as int
          : int.tryParse('${json['concurrent_viewers']}'),
      scheduledStartTime: DateTime.tryParse(
        json['scheduled_start_time']?.toString() ?? '',
      ),
    );
  }
}

class LiveBroadcastRepository {
  /// Checks whether the configured (or given) YouTube video is actually
  /// live right now. Always resolves — never throws — since this drives
  /// a status badge, not core functionality; a failed check should just
  /// leave the badge in its "unknown" state rather than surface an error
  /// to the user.
  Future<YoutubeBroadcastInfo> fetchBroadcastStatus({String? videoId}) async {
    try {
      final response = await ApiService.get(
        'live/messages/youtube-status',
        queryParams: videoId == null ? null : {'video_id': videoId},
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ YouTube broadcast status check failed: HTTP ${response.statusCode}',
        );
        return YoutubeBroadcastInfo.unknown();
      }

      final data = json.decode(response.body);
      if (data['status'] != 'success') {
        debugPrint('⚠️ YouTube broadcast status error: ${data['message']}');
        return YoutubeBroadcastInfo.unknown();
      }

      return YoutubeBroadcastInfo.fromJson(
        data['data'] as Map<String, dynamic>? ?? {},
      );
    } catch (e) {
      debugPrint('⚠️ Error checking YouTube broadcast status: $e');
      return YoutubeBroadcastInfo.unknown();
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }
}
