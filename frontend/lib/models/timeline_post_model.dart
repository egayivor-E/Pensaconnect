// lib/models/timeline_post_model.dart

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

  factory TimelinePost.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? user = json['user'] as Map<String, dynamic>?;
    return TimelinePost(
      id: (json['id'] as num).toInt(),
      content: json['content'] ?? '',
      imageUrl: json['imageUrl'] as String?,
      isVideo: json['isVideo'] == true,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      userId:
          (json['userId'] as num?)?.toInt() ??
          (user?['id'] as num?)?.toInt() ??
          0,
      authorName: (user?['fullName'] as String?)?.trim().isNotEmpty == true
          ? user!['fullName'] as String
          : (user?['username'] as String? ?? 'You'),
      authorAvatarUrl: user?['profilePicture'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      hasLiked: json['likedByMe'] == true || json['hasLiked'] == true,
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
    return TimelineComment(
      id: (json['id'] as num).toInt(),
      content: json['content'] ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      authorName: (user?['fullName'] as String?)?.trim().isNotEmpty == true
          ? user!['fullName'] as String
          : (user?['username'] as String? ?? 'Someone'),
      authorAvatarUrl: user?['profilePicture'] as String?,
      authorId: (user?['id'] as num?)?.toInt(),
    );
  }
}
