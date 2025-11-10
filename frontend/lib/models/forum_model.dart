// forum_models.dart
// ✅ Fully consistent models for posts, comments, attachments, and events.

class ForumAttachment {
  final int id;
  final String url;
  final String fileName;
  final String mimeType;

  ForumAttachment({
    required this.id,
    required this.url,
    required this.fileName,
    required this.mimeType,
  });

  factory ForumAttachment.fromJson(Map<String, dynamic> json) {
    int _parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return ForumAttachment(
      id: _parseInt(json['id']),
      url: json['url'] ?? '',
      fileName: json['file_name'] ?? '',
      mimeType: json['mime_type'] ?? 'application/octet-stream',
    );
  }

  Map<String, dynamic> toJson() => {
    "id": id,
    "url": url,
    "file_name": fileName,
    "mime_type": mimeType,
  };
}

class ForumPost {
  final int id;
  final String title;
  final String content;
  final int threadId;
  final int authorId;
  final String authorName;
  final String? authorAvatar;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ForumAttachment> attachments;

  int likeCount;
  bool likedByMe;
  int commentsCount;

  ForumPost({
    required this.id,
    required this.title,
    required this.content,
    required this.threadId,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    this.createdAt,
    this.updatedAt,
    this.attachments = const [],
    this.likeCount = 0,
    this.likedByMe = false,
    this.commentsCount = 0,
  });

  factory ForumPost.fromJson(Map<String, dynamic> json) {
    int _parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return ForumPost(
      id: _parseInt(json['id']),
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      threadId: _parseInt(json['thread_id']),
      authorId: _parseInt(json['author_id']),
      authorName: json['author_name'] ?? 'Unknown',
      authorAvatar: json['author_avatar'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .map((a) => ForumAttachment.fromJson(a))
          .toList(),
      likeCount: _parseInt(json['like_count']),
      likedByMe: json['liked_by_me'] ?? false,
      commentsCount: _parseInt(json['comments_count']),
    );
  }

  Map<String, dynamic> toJson() => {
    "id": id,
    "title": title,
    "content": content,
    "thread_id": threadId,
    "author_id": authorId,
    "author_name": authorName,
    "author_avatar": authorAvatar,
    "created_at": createdAt?.toIso8601String(),
    "updated_at": updatedAt?.toIso8601String(),
    "attachments": attachments.map((a) => a.toJson()).toList(),
    "like_count": likeCount,
    "liked_by_me": likedByMe,
    "comments_count": commentsCount,
  };
}

class ForumComment {
  final int id;
  final int postId;
  final int authorId;
  final String authorName;
  final String? authorAvatar;
  final String content;
  final DateTime? createdAt;
  final List<ForumAttachment> attachments;

  ForumComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.content,
    this.createdAt,
    this.attachments = const [],
  });

  factory ForumComment.fromJson(Map<String, dynamic> json) {
    int _parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return ForumComment(
      id: _parseInt(json['id']),
      postId: _parseInt(json['post_id']),
      authorId: _parseInt(json['author_id']),
      authorName: json['author_name'] ?? 'Unknown',
      authorAvatar: json['author_avatar'],
      content: json['content'] ?? '',
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .map((a) => ForumAttachment.fromJson(a))
          .toList(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    "id": id,
    "post_id": postId,
    "author_id": authorId,
    "author_name": authorName,
    "author_avatar": authorAvatar,
    "content": content,
    "attachments": attachments.map((a) => a.toJson()).toList(),
    "created_at": createdAt?.toIso8601String(),
  };
}

/// ✅ Event models to work with eventBus in ForumDetailScreen

class PostCreatedEvent {
  final int threadId;
  final ForumPost post;

  PostCreatedEvent({required this.threadId, required this.post});
}

class CommentCreatedEvent {
  final int threadId;
  final int postId;
  final ForumComment comment;

  CommentCreatedEvent({
    required this.threadId,
    required this.postId,
    required this.comment,
  });
}

class PostDeletedEvent {
  final int threadId;
  final int postId;

  PostDeletedEvent({required this.threadId, required this.postId});
}
