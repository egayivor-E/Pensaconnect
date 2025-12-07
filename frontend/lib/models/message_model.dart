class Message {
  final String? id; // DB message id (optional for live stream)
  final String? groupId; // Chat group id
  final String senderId; // Unique sender id
  final String senderName; // Human-readable name
  final String content; // Message content
  final DateTime timestamp;
  final String messageType; // ✅ Already defined but missing in constructor

  Message({
    this.id,
    this.groupId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    required this.messageType, // ✅ Add this to constructor
  });

  /// Factory: create a `Message` instance from API JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString(),
      groupId: json['group_id']?.toString() ?? json['groupId'],
      senderId:
          json['sender_id']?.toString() ??
          json['sender']?.toString() ??
          "unknown",
      senderName:
          json['sender_name']?.toString() ??
          json['user']?.toString() ??
          "Unknown",
      content: json['content']?.toString() ?? "",
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? "") ??
          DateTime.now(),
      messageType: json['message_type']?.toString() ?? 'text', // ✅ Add this
    );
  }

  /// Convert a `Message` instance to JSON (for sending to API)
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (groupId != null) 'group_id': groupId,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'message_type': messageType, // ✅ Add this
    };
  }
}
