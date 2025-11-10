// lib/models/testimony_model.dart

class Testimony {
  final String id;
  final String title;
  final String content;
  final String authorName;
  final String authorId;
  final String? imageUrl;
  final DateTime createdAt;
  final int likesCount;
  final int commentsCount;
  final bool likedByMe;

  Testimony({
    required this.id,
    required this.title,
    required this.content,
    required this.authorName,
    required this.authorId,
    this.imageUrl,
    required this.createdAt,
    required this.likesCount,
    required this.commentsCount,
    required this.likedByMe,
  });

  /// Helpers
  static String _extractString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is int) return value.toString();
    if (value is double) return value.toString();
    if (value is Map && value.isNotEmpty) {
      return value.values.first.toString();
    }
    return value.toString();
  }

  static int _extractInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static bool _extractBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  static DateTime _extractDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    final parsed = DateTime.tryParse(value.toString());
    return parsed ?? DateTime.now();
  }

  /// Factory
  factory Testimony.fromJson(Map<String, dynamic> json) {
    final dynamic user = json['user'];

    String authorName = 'Anonymous';
    String authorId = '';

    if (user is Map<String, dynamic>) {
      authorName = _extractString(
        user['username'] ?? user['name'] ?? user['user'],
      );
      if (authorName.isEmpty) authorName = 'Anonymous';
      authorId = _extractString(user['id'] ?? user['user_id'] ?? user['uuid']);
    } else if (user is String) {
      authorName = user;
    } else if (json['authorName'] != null) {
      authorName = _extractString(json['authorName']);
    }

    return Testimony(
      id: _extractString(json['id']),
      title: _extractString(json['title']),
      content: _extractString(json['content']),
      authorName: authorName,
      authorId: authorId,
      imageUrl: json['image_url']?.toString(),
      createdAt: _extractDate(
        json['created_at'] ?? json['createdAt'] ?? json['timestamp'],
      ),
      likesCount: _extractInt(json['likes_count'] ?? json['likes']),
      commentsCount: _extractInt(json['comments_count'] ?? json['comments']),
      likedByMe: _extractBool(json['liked_by_me'] ?? json['likedByMe']),
    );
  }

  Testimony copyWith({
    String? title,
    String? content,
    String? imageUrl,
    int? likesCount,
    int? commentsCount,
    bool? likedByMe,
  }) {
    return Testimony(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorName: authorName,
      authorId: authorId,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      likedByMe: likedByMe ?? this.likedByMe,
    );
  }
}

class TestimonyComment {
  final String id;
  final String authorName;
  final String content;
  final DateTime createdAt;

  TestimonyComment({
    required this.id,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  factory TestimonyComment.fromJson(Map<String, dynamic> json) {
    final dynamic user = json['user'];

    String authorName = 'Anonymous';
    if (user is Map<String, dynamic>) {
      authorName = Testimony._extractString(
        user['username'] ?? user['name'] ?? user['user'],
      );
      if (authorName.isEmpty) authorName = 'Anonymous';
    } else if (user is String) {
      authorName = user;
    } else if (json['authorName'] != null) {
      authorName = Testimony._extractString(json['authorName']);
    }

    return TestimonyComment(
      id: Testimony._extractString(json['id']),
      authorName: authorName,
      content: Testimony._extractString(json['content']),
      createdAt: Testimony._extractDate(
        json['created_at'] ?? json['createdAt'] ?? json['timestamp'],
      ),
    );
  }
}
