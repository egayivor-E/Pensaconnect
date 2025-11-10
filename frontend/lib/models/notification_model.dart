// lib/models/notification_model.dart
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? type;
  final DateTime createdAt;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    required this.createdAt,
    this.isRead = false,
  });

  /// Convert JSON → AppNotification
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '', // ✅ always safe string
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      type: json['type']?.toString(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead:
          json['is_read'] == true || json['is_read'] == 1, // ✅ handle bool/int
    );
  }

  /// Convert AppNotification → JSON
  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "title": title,
      "body": body,
      "type": type,
      "created_at": createdAt.toIso8601String(),
      "is_read": isRead,
    };
  }
}
