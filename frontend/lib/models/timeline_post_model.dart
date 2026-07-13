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

  TimelinePost({
    required this.id,
    required this.content,
    this.imageUrl,
    this.isVideo = false,
    required this.createdAt,
    required this.userId,
    required this.authorName,
    this.authorAvatarUrl,
  });

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
    );
  }
}
