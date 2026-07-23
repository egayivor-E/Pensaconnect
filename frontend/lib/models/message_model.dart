class Message {
  final String? id; // DB message id (optional for live stream)
  final String? groupId; // Chat group id
  final String senderId; // Unique sender id
  final String senderName; // Human-readable name
  // ✅ FIX: previously there was nowhere to carry the sender's avatar at
  // all, so every message bubble fell back to a generic person icon
  // regardless of whether the sender actually had a profile picture.
  final String? senderProfilePicture;
  final String content; // Message content
  final DateTime timestamp;
  final String messageType; // ✅ Already defined but missing in constructor

  Message({
    this.id,
    this.groupId,
    required this.senderId,
    required this.senderName,
    this.senderProfilePicture,
    required this.content,
    required this.timestamp,
    required this.messageType, // ✅ Add this to constructor
  });

  /// Factory: create a `Message` instance from API JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    // ✅ FIX: the backend (see backend/api/v1/live.py and the
    // `send_message` socket handler) sends sender details nested under a
    // `sender` object — `{id, username, full_name, profile_picture}` —
    // not as flat `sender_name`/`user` keys. Reading only the flat keys
    // meant senderName silently fell back to "Unknown" for every real
    // live-stream message, and the profile picture was never read at
    // all. Both the nested object and the old flat keys are checked, so
    // this stays compatible with any other caller still using the old
    // shape.
    final sender = json['sender'];
    final senderMap = sender is Map
        ? Map<String, dynamic>.from(sender)
        : <String, dynamic>{};

    return Message(
      id: json['id']?.toString(),
      groupId: json['group_id']?.toString() ?? json['groupId'],
      senderId:
          senderMap['id']?.toString() ??
          json['sender_id']?.toString() ??
          json['senderId']?.toString() ??
          "unknown",
      senderName:
          senderMap['full_name']?.toString() ??
          senderMap['username']?.toString() ??
          json['sender_name']?.toString() ??
          json['user']?.toString() ??
          "Unknown",
      senderProfilePicture:
          senderMap['profile_picture']?.toString() ??
          json['sender_profile_picture']?.toString(),
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
      if (senderProfilePicture != null)
        'sender_profile_picture': senderProfilePicture,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'message_type': messageType, // ✅ Add this
    };
  }
}
