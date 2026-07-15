class TimelinePost {
  final int id;
  final String content;
  final String? imageUrl;
  final bool isVideo;
  final DateTime createdAt;
  final int userId;
  final String authorName;
  final String? authorAvatarUrl;
  final int likeCount;
  final int commentCount;
  final bool hasLiked;

  TimelinePost({
    required this.id,
    required this.content,
    this.imageUrl,
    this.isVideo = false,
    required this.createdAt,
    required this.userId,
    required this.authorName,
    this.authorAvatarUrl,
    this.likeCount = 0,
    this.commentCount = 0,
    this.hasLiked = false,
  });

  TimelinePost copyWith({int? likeCount, int? commentCount, bool? hasLiked}) {
    return TimelinePost(
      id: id,
      content: content,
      imageUrl: imageUrl,
      isVideo: isVideo,
      createdAt: createdAt,
      userId: userId,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      hasLiked: hasLiked ?? this.hasLiked,
    );
  }

  // Reads a key from JSON trying snake_case first (what the Flask API
  // actually returns via to_dict()/success_response), then falling
  // back to camelCase in case a future endpoint switches conventions.
  static T? _pick<T>(Map<String, dynamic> json, String snake, String camel) {
    if (json.containsKey(snake) && json[snake] != null)
      return json[snake] as T?;
    if (json.containsKey(camel) && json[camel] != null)
      return json[camel] as T?;
    return null;
  }

  factory TimelinePost.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? user = json['user'] as Map<String, dynamic>?;

    final fullName = (user?['fullName'] ?? user?['full_name']) as String?;
    final username = user?['username'] as String?;
    final avatar =
        (user?['profilePicture'] ?? user?['profile_picture']) as String?;
    final authorUserId = (user?['id'] as num?)?.toInt();

    return TimelinePost(
      id: (json['id'] as num).toInt(),
      content: json['content'] as String? ?? '',
      imageUrl: _pick<String>(json, 'image_url', 'imageUrl'),
      isVideo: _pick<bool>(json, 'is_video', 'isVideo') == true,
      createdAt:
          DateTime.tryParse(
            _pick<String>(json, 'created_at', 'createdAt') ?? '',
          ) ??
          DateTime.now(),
      userId:
          _pick<num>(json, 'user_id', 'userId')?.toInt() ?? authorUserId ?? 0,
      authorName: (fullName?.trim().isNotEmpty ?? false)
          ? fullName!
          : (username ?? 'Member'),
      authorAvatarUrl: avatar,
      likeCount: _pick<num>(json, 'like_count', 'likeCount')?.toInt() ?? 0,
      commentCount:
          _pick<num>(json, 'comment_count', 'commentCount')?.toInt() ?? 0,
      hasLiked:
          _pick<bool>(json, 'has_liked', 'hasLiked') == true ||
          json['likedByMe'] == true,
    );
  }
}

class TimelineComment {
  final int id;
  final String content;
  final DateTime createdAt;
  final String authorName;
  final String? authorAvatarUrl;
  final int? authorId;

  TimelineComment({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.authorName,
    this.authorAvatarUrl,
    this.authorId,
  });

  factory TimelineComment.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? user = json['user'] as Map<String, dynamic>?;
    final fullName = (user?['fullName'] ?? user?['full_name']) as String?;
    final username = user?['username'] as String?;
    final avatar =
        (user?['profilePicture'] ?? user?['profile_picture']) as String?;

    return TimelineComment(
      id: (json['id'] as num).toInt(),
      content: json['content'] as String? ?? '',
      createdAt:
          DateTime.tryParse(
            (json['created_at'] ?? json['createdAt'])?.toString() ?? '',
          ) ??
          DateTime.now(),
      authorName: (fullName?.trim().isNotEmpty ?? false)
          ? fullName!
          : (username ?? 'Someone'),
      authorAvatarUrl: avatar,
      authorId: (user?['id'] as num?)?.toInt(),
    );
  }
}
