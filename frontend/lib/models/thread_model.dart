class Thread {
  final int id;
  final String title;
  final String description;
  final int? authorId;
  final DateTime? createdAt;

  Thread({
    required this.id,
    required this.title,
    required this.description,
    this.authorId,
    this.createdAt,
  });

  factory Thread.fromJson(Map<String, dynamic> json) {
    return Thread(
      id: json['id'] as int,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      authorId: json['author_id'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}
