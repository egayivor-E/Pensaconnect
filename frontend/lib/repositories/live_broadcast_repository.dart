// lib/repositories/live_broadcast_repository.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/live_broadcast_model.dart';
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

  /// Everyone logged in can see who is currently live, on any platform.
  /// Maps to GET /live/broadcasts (public-safe shape — never includes
  /// RTMP credentials, see LiveBroadcast.to_dict on the backend).
  Future<List<LiveBroadcast>> listLiveBroadcasts() async {
    try {
      final response = await ApiService.get(
        'live/broadcasts',
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode != 200) {
        debugPrint('❌ Failed to load live broadcasts: ${response.statusCode}');
        throw Exception(
          'Failed to load live broadcasts: ${response.statusCode}',
        );
      }

      final data = json.decode(response.body);
      final list = data['data'];
      if (list is! List) return [];

      return list
          .map<LiveBroadcast>(
            (item) => LiveBroadcast.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('❌ Error fetching live broadcasts: $e');
      rethrow;
    }
  }

  /// The requesting user's own recent broadcasts, including RTMP stream
  /// key details for native ones. Maps to GET /live/broadcasts/mine.
  Future<List<LiveBroadcast>> myBroadcasts() async {
    try {
      final response = await ApiService.get(
        'live/broadcasts/mine',
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode != 200) {
        debugPrint('❌ Failed to load your broadcasts: ${response.statusCode}');
        throw Exception(
          'Failed to load your broadcasts: ${response.statusCode}',
        );
      }

      final data = json.decode(response.body);
      final list = data['data'];
      if (list is! List) return [];

      return list
          .map<LiveBroadcast>(
            (item) => LiveBroadcast.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('❌ Error fetching your broadcasts: $e');
      rethrow;
    }
  }

  /// Whether the current user is allowed to start a broadcast right now
  /// (admin, or explicitly granted `can_go_live`). Maps to
  /// GET /live/broadcasts/permission. Prefer `UserModel.canStartBroadcast`
  /// (from the already-loaded profile) where available — this exists for
  /// screens that want a fresh server-side check.
  Future<bool> canGoLive() async {
    try {
      final response = await ApiService.get(
        'live/broadcasts/permission',
        headers: await _getAuthHeaders(),
      );
      if (response.statusCode != 200) return false;
      final data = json.decode(response.body);
      return (data['data'] as Map?)?['can_go_live'] == true;
    } catch (e) {
      debugPrint('⚠️ Error checking go-live permission: $e');
      return false;
    }
  }

  /// Starts a new broadcast. For youtube/facebook, [streamRef] is required
  /// (the video ID or public video URL respectively). For native, no
  /// [streamRef] is needed — the backend provisions a Mux live stream and
  /// the returned [LiveBroadcast] carries the RTMP ingest URL + stream key
  /// (see LiveBroadcast.rtmpUrl / rtmpStreamKey) for the broadcaster to
  /// plug into their encoder of choice (e.g. OBS, Larix Broadcaster).
  /// Maps to POST /live/broadcasts.
  Future<LiveBroadcast> startBroadcast({
    required LiveBroadcastPlatform platform,
    String? title,
    String? streamRef,
  }) async {
    try {
      final body = <String, dynamic>{'platform': platform.toJson()};
      if (title != null && title.trim().isNotEmpty) {
        body['title'] = title.trim();
      }
      if (streamRef != null && streamRef.trim().isNotEmpty) {
        body['stream_ref'] = streamRef.trim();
      }

      final response = await ApiService.post(
        'live/broadcasts',
        body,
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode != 201) {
        debugPrint('❌ Failed to start broadcast: ${response.statusCode}');
        throw Exception('Failed to start broadcast: ${response.statusCode}');
      }

      final data = json.decode(response.body);
      return LiveBroadcast.fromJson(
        Map<String, dynamic>.from(data['data'] as Map),
      );
    } catch (e) {
      debugPrint('❌ Error starting broadcast: $e');
      rethrow;
    }
  }

  /// Ends a broadcast the current user owns (or, if admin, any broadcast).
  /// Maps to PATCH /live/broadcasts/<id> with is_live: false.
  Future<LiveBroadcast> endBroadcast(int broadcastId) async {
    try {
      final response = await ApiService.patch('live/broadcasts/$broadcastId', {
        'is_live': false,
      });

      if (response.statusCode != 200) {
        debugPrint('❌ Failed to end broadcast: ${response.statusCode}');
        throw Exception('Failed to end broadcast: ${response.statusCode}');
      }

      final data = json.decode(response.body);
      return LiveBroadcast.fromJson(
        Map<String, dynamic>.from(data['data'] as Map),
      );
    } catch (e) {
      debugPrint('❌ Error ending broadcast: $e');
      rethrow;
    }
  }

  /// Edits a youtube/facebook broadcast's title or stream_ref. Not valid
  /// for native broadcasts (the backend ignores stream_ref there).
  Future<LiveBroadcast> updateBroadcast(
    int broadcastId, {
    String? title,
    String? streamRef,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (streamRef != null) body['stream_ref'] = streamRef;

      final response = await ApiService.patch(
        'live/broadcasts/$broadcastId',
        body,
      );

      if (response.statusCode != 200) {
        debugPrint('❌ Failed to update broadcast: ${response.statusCode}');
        throw Exception('Failed to update broadcast: ${response.statusCode}');
      }

      final data = json.decode(response.body);
      return LiveBroadcast.fromJson(
        Map<String, dynamic>.from(data['data'] as Map),
      );
    } catch (e) {
      debugPrint('❌ Error updating broadcast: $e');
      rethrow;
    }
  }

  /// Admin-only: grant or revoke another user's permission to go live.
  /// Maps to PATCH /users/<id>/broadcast-permission.
  Future<void> setBroadcastPermission(int userId, bool canGoLive) async {
    try {
      final response = await ApiService.patch(
        'users/$userId/broadcast-permission',
        {'can_go_live': canGoLive},
      );

      if (response.statusCode != 200) {
        debugPrint(
          '❌ Failed to update broadcast permission: ${response.statusCode}',
        );
        throw Exception(
          'Failed to update broadcast permission: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error updating broadcast permission: $e');
      rethrow;
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
