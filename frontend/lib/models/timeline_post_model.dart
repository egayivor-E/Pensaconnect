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
    this.hasLiked = false,
  });

  factory TimelinePost.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? user = json['user'] as Map<String, dynamic>?;
    return TimelinePost(
      id: (json['id'] as num).toInt(),
      content: json['content'] ?? '',
      imageUrl: json['image_url'] as String?,
      isVideo: json['is_video'] == true,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      userId:
          (json['user_id'] as num?)?.toInt() ??
          (user?['id'] as num?)?.toInt() ??
          0,
      authorName: (user?['full_name'] as String?)?.trim().isNotEmpty == true
          ? user!['full_name'] as String
          : (user?['username'] as String? ?? 'You'),
      authorAvatarUrl: user?['profile_picture'] as String?,
      // ✅ Reactions: the server is expected to return these the same way
      // Activity already does (see Activity.hasLiked / likeCount) — a
      // per-post like count and whether the current user has liked it.
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      hasLiked: json['has_liked'] == true,
    );
  }

  // Lets the profile screen apply an optimistic like/unlike (and roll it
  // back on failure) without re-fetching the whole post list — same
  // reasoning as Activity.copyWith in the home feed.
  TimelinePost copyWith({int? likeCount, bool? hasLiked}) {
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
      hasLiked: hasLiked ?? this.hasLiked,
    );
  }
}
