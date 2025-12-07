class WorshipSong {
  final String id;
  final String title;
  final String artist;
  final String? videoId;
  final String? videoUrl;
  final String? audioUrl;
  final String thumbnailUrl;
  final int category; // 0 = English, 1 = African
  final String mediaType; // 'youtube', 'audio', 'video' - MATCHES FLASK
  final String? lyrics;
  final int duration;
  final int? fileSize; // NEW: From Flask backend
  final bool allowDownload; // NEW: From Flask backend
  final int downloadCount; // NEW: From Flask backend
  final DateTime createdAt; // CHANGED: Not nullable in Flask

  const WorshipSong({
    required this.id,
    required this.title,
    required this.artist,
    this.videoId,
    this.videoUrl,
    this.audioUrl,
    required this.thumbnailUrl,
    required this.category,
    required this.mediaType, // CHANGED: Uses Flask's media_type
    this.lyrics,
    this.duration = 0,
    this.fileSize,
    this.allowDownload = true,
    this.downloadCount = 0,
    required this.createdAt, // CHANGED: Required from Flask
  });

  // Helper getters for Flutter app compatibility
  bool get isYouTube => mediaType == 'youtube';
  bool get isAudio => mediaType == 'audio';
  bool get isVideo => mediaType == 'video';

  // Helper method to get media source
  String get mediaSource {
    if (isYouTube) return videoId!;
    if (isAudio) return audioUrl!;
    return videoUrl!;
  }

  // For offline support (Flutter-only, not from Flask)
  bool get isDownloadable => allowDownload;
  bool get isAvailableOffline => false; // You'll manage this locally

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'video_id': videoId, // CHANGED: Matches Flask snake_case
      'video_url': videoUrl, // CHANGED: Matches Flask snake_case
      'audio_url': audioUrl, // CHANGED: Matches Flask snake_case
      'thumbnail_url': thumbnailUrl, // CHANGED: Matches Flask snake_case
      'category': category,
      'media_type': mediaType, // CHANGED: Matches Flask
      'lyrics': lyrics,
      'duration': duration,
      'file_size': fileSize, // CHANGED: Matches Flask snake_case
      'allow_download': allowDownload, // CHANGED: Matches Flask snake_case
    };
  }

  factory WorshipSong.fromJson(Map<String, dynamic> json) {
    print('🔄 Parsing WorshipSong JSON: $json');

    try {
      // ✅ FIX: Handle both camelCase and snake_case field names
      String? getField(String camelCase, String snakeCase) {
        return json[camelCase]?.toString() ?? json[snakeCase]?.toString();
      }

      int? getIntField(String camelCase, String snakeCase) {
        return json[camelCase] as int? ?? json[snakeCase] as int?;
      }

      bool? getBoolField(String camelCase, String snakeCase) {
        return json[camelCase] as bool? ?? json[snakeCase] as bool?;
      }

      return WorshipSong(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Unknown Title',
        artist: json['artist']?.toString() ?? 'Unknown Artist',
        // ✅ FIX: Check both field naming conventions
        videoId: getField('videoId', 'video_id'),
        videoUrl: getField('videoUrl', 'video_url'),
        audioUrl: getField('audioUrl', 'audio_url'),
        thumbnailUrl:
            getField('thumbnailUrl', 'thumbnail_url') ??
            'assets/images/worship_icon.jpeg',
        category: (json['category'] as int?) ?? 0,
        mediaType: getField('mediaType', 'media_type') ?? 'youtube',
        lyrics: getField('lyrics', 'lyrics'),
        duration: getIntField('duration', 'duration') ?? 0,
        fileSize: getIntField('fileSize', 'file_size'),
        allowDownload: getBoolField('allowDownload', 'allow_download') ?? true,
        downloadCount: getIntField('downloadCount', 'download_count') ?? 0,
        // ✅ FIX: Handle created_at parsing
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'].toString())
            : DateTime.now(),
      );
    } catch (e) {
      print('❌ Critical error parsing WorshipSong: $e');
      print('❌ Problematic JSON: $json');

      // Return a default song instead of crashing
      return WorshipSong(
        id: 'error-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Error Loading Song',
        artist: 'Unknown',
        thumbnailUrl: 'assets/images/worship_icon.jpeg',
        category: 0,
        mediaType: 'audio',
        createdAt: DateTime.now(),
      );
    }
  }

  // Copy with method for updates
  WorshipSong copyWith({
    String? title,
    String? artist,
    String? videoId,
    String? videoUrl,
    String? audioUrl,
    String? thumbnailUrl,
    int? category,
    String? mediaType,
    String? lyrics,
    int? duration,
    int? fileSize,
    bool? allowDownload,
    int? downloadCount,
  }) {
    return WorshipSong(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      videoId: videoId ?? this.videoId,
      videoUrl: videoUrl ?? this.videoUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      category: category ?? this.category,
      mediaType: mediaType ?? this.mediaType,
      lyrics: lyrics ?? this.lyrics,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      allowDownload: allowDownload ?? this.allowDownload,
      downloadCount: downloadCount ?? this.downloadCount,
      createdAt: createdAt,
    );
  }

  // For local offline management (not part of Flask model)
  WorshipSong withLocalPath(String localPath) {
    return WorshipSong(
      id: id,
      title: title,
      artist: artist,
      videoId: videoId,
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      thumbnailUrl: thumbnailUrl,
      category: category,
      mediaType: mediaType,
      lyrics: lyrics,
      duration: duration,
      fileSize: fileSize,
      allowDownload: allowDownload,
      downloadCount: downloadCount,
      createdAt: createdAt,
    );
  }
}
