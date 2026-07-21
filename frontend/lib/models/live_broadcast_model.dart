// lib/models/live_broadcast_model.dart
import 'package:flutter/material.dart';

/// Mirrors backend/models.py `LiveBroadcast.PLATFORMS`.
enum LiveBroadcastPlatform {
  youtube,
  facebook,
  native;

  static LiveBroadcastPlatform fromJson(String? value) {
    switch (value) {
      case 'youtube':
        return LiveBroadcastPlatform.youtube;
      case 'facebook':
        return LiveBroadcastPlatform.facebook;
      case 'native':
        return LiveBroadcastPlatform.native;
      default:
        debugPrint('⚠️ Unknown broadcast platform: $value');
        return LiveBroadcastPlatform.youtube;
    }
  }

  String toJson() => switch (this) {
    LiveBroadcastPlatform.youtube => 'youtube',
    LiveBroadcastPlatform.facebook => 'facebook',
    LiveBroadcastPlatform.native => 'native',
  };

  String get label => switch (this) {
    LiveBroadcastPlatform.youtube => 'YouTube',
    LiveBroadcastPlatform.facebook => 'Facebook',
    LiveBroadcastPlatform.native => 'In-app',
  };
}

class LiveBroadcaster {
  final int id;
  final String username;
  final String fullName;
  final String? profilePicture;

  const LiveBroadcaster({
    required this.id,
    required this.username,
    required this.fullName,
    this.profilePicture,
  });

  factory LiveBroadcaster.fromJson(Map<String, dynamic> json) {
    return LiveBroadcaster(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      username: json['username']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? 'Unknown',
      profilePicture: json['profile_picture']?.toString(),
    );
  }
}

/// Mirrors backend/models.py `LiveBroadcast.to_dict()` /
/// `to_broadcaster_dict()` (see backend/api/v1/broadcasts.py).
///
/// [rtmpStreamKey] and [rtmpUrl] are only ever populated when this instance
/// came from an endpoint scoped to the broadcast's own owner/admin
/// (POST /live/broadcasts, PATCH .../<id>, GET .../mine) — the public
/// GET /live/broadcasts list never includes them. Never send these to
/// anything other than the broadcaster's own encoder.
class LiveBroadcast {
  final int id;
  final int userId;
  final LiveBroadcastPlatform platform;
  final String title;
  final String? streamRef;
  final String? playbackId;
  final bool isLive;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final LiveBroadcaster? broadcaster;
  final String? muxStreamId;
  final String? rtmpStreamKey;
  final String? rtmpUrl;

  const LiveBroadcast({
    required this.id,
    required this.userId,
    required this.platform,
    required this.title,
    this.streamRef,
    this.playbackId,
    required this.isLive,
    this.startedAt,
    this.endedAt,
    this.broadcaster,
    this.muxStreamId,
    this.rtmpStreamKey,
    this.rtmpUrl,
  });

  /// For `platform == native`, playback happens over Mux's public HLS URL
  /// built from [playbackId] — see https://docs.mux.com/guides/play-your-videos.
  String? get hlsPlaybackUrl =>
      playbackId == null ? null : 'https://stream.mux.com/$playbackId.m3u8';

  factory LiveBroadcast.fromJson(Map<String, dynamic> json) {
    return LiveBroadcast(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      userId: json['user_id'] is int
          ? json['user_id'] as int
          : int.tryParse('${json['user_id']}') ?? 0,
      platform: LiveBroadcastPlatform.fromJson(json['platform'] as String?),
      title: json['title']?.toString() ?? 'Live Stream',
      streamRef: json['stream_ref']?.toString(),
      playbackId: json['playback_id']?.toString(),
      isLive: json['is_live'] == true,
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? ''),
      broadcaster: json['broadcaster'] is Map
          ? LiveBroadcaster.fromJson(
              Map<String, dynamic>.from(json['broadcaster'] as Map),
            )
          : null,
      muxStreamId: json['mux_stream_id']?.toString(),
      rtmpStreamKey: json['rtmp_stream_key']?.toString(),
      rtmpUrl: json['rtmp_url']?.toString(),
    );
  }
}
