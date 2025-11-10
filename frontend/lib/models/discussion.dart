class Comment {
  final String user;
  final String content;
  final DateTime createdAt;

  Comment({required this.user, required this.content, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();
}

class Discussion {
  final String title;
  final String content;
  final String user;
  final DateTime createdAt;
  final String category;
  int likes;
  final List<Comment> comments;

  Discussion({
    required this.title,
    required this.content,
    required this.user,
    this.category = 'Faith',
    DateTime? createdAt,
    this.likes = 0,
    List<Comment>? comments,
  }) : createdAt = createdAt ?? DateTime.now(),
       comments = comments ?? [];
}
