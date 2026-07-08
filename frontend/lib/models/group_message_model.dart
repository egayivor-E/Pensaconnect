import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class GroupMessage {
  final int id;
  final String uuid;
  final int groupChatId;
  final int senderId;
  final String content;
  final String messageType; // 'text', 'image', 'file', 'system'
  final List<dynamic> attachments;
  final int? repliedToId;
  final List<dynamic> readBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final Map<String, dynamic>? metaData;
  final bool isTemporary;
  final String status;
  final bool? isLocal;

  // Sender details
  final Map<String, dynamic>? sender;

  // Replied message (optional)
  final Map<String, dynamic>? repliedTo;

  GroupMessage({
    required this.id,
    required this.uuid,
    required this.groupChatId,
    required this.senderId,
    required this.content,
    required this.messageType,
    required this.attachments,
    this.repliedToId,
    required this.readBy,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    this.metaData,
    this.sender,
    this.repliedTo,
    this.isTemporary = false,
    this.status = 'sent',
    this.isLocal = false,
  });

  // Socket.IO factory constructor
  factory GroupMessage.fromSocketIO(Map<String, dynamic> json) {
    debugPrint('🔌 Creating GroupMessage from Socket.IO data: $json');

    return GroupMessage(
      id: _parseInt(json['id']),
      uuid: '', // Socket.IO might not send UUID
      groupChatId: _parseInt(json['groupId']),
      senderId: _parseSenderId(json), // Use the improved parser
      content: _parseString(json['content']),
      messageType: _parseString(json['messageType']) ?? 'text',
      attachments: _parseList(json['attachments']),
      repliedToId: null,
      readBy: _parseList(json['readBy']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['createdAt']),
      isActive: true,
      sender: _parseSenderObject(json),
    );
  }

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    debugPrint('🔍 Parsing GroupMessage from JSON');
    debugPrint('📋 JSON keys: ${json.keys}');

    // Parse sender ID using improved parser
    final senderId = _parseSenderId(json);

    // Parse sender object
    final sender = _parseSenderObject(json);

    return GroupMessage(
      id: _parseInt(json['id']),
      uuid: _parseString(json['uuid']),
      groupChatId: _parseInt(json['group_chat_id'] ?? json['groupId']),
      senderId: senderId,
      content: _parseString(json['content']),
      messageType:
          _parseString(json['message_type'] ?? json['messageType']) ?? 'text',
      attachments: _parseList(json['attachments']),
      repliedToId: _parseNullableInt(
        json['replied_to_id'] ?? json['repliedToId'],
      ),
      readBy: _parseList(json['read_by'] ?? json['readBy']),
      createdAt: _parseDateTime(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDateTime(
        json['updated_at'] ?? json['updatedAt'] ?? json['createdAt'],
      ),
      isActive: _parseBool(json['is_active'] ?? json['isActive']),
      metaData: _parseMap(json['meta_data'] ?? json['metaData']),
      sender: sender,
      repliedTo: _parseMap(json['replied_to'] ?? json['repliedTo']),
    );
  }

  // ✅ IMPROVED: Parse sender ID with multiple fallback options
  static int _parseSenderId(Map<String, dynamic> json) {
    // Debug what we received
    debugPrint('🔍 Looking for sender ID in: ${json.keys}');
    
    // 1. Try direct sender_id (REST API format)
    if (json.containsKey('sender_id')) {
      final id = _parseInt(json['sender_id']);
      if (id > 0) {
        debugPrint('✅ Found sender_id: $id');
        return id;
      }
    }
    
    // 2. Try senderId (alternative naming)
    if (json.containsKey('senderId')) {
      final id = _parseInt(json['senderId']);
      if (id > 0) {
        debugPrint('✅ Found senderId: $id');
        return id;
      }
    }
    
    // 3. Try userId (WebSocket sometimes uses this)
    if (json.containsKey('userId')) {
      final id = _parseInt(json['userId']);
      if (id > 0) {
        debugPrint('✅ Found userId: $id');
        return id;
      }
    }
    
    // 4. Try user_id (WebSocket alternative)
    if (json.containsKey('user_id')) {
      final id = _parseInt(json['user_id']);
      if (id > 0) {
        debugPrint('✅ Found user_id: $id');
        return id;
      }
    }
    
    // 5. Try from sender object
    if (json.containsKey('sender') && json['sender'] is Map) {
      final senderMap = json['sender'] as Map;
      debugPrint('🔍 Checking sender object: $senderMap');
      
      // Try different ID fields in sender object
      if (senderMap.containsKey('id')) {
        final id = _parseInt(senderMap['id']);
        if (id > 0) {
          debugPrint('✅ Found sender.id: $id');
          return id;
        }
      }
      if (senderMap.containsKey('userId')) {
        final id = _parseInt(senderMap['userId']);
        if (id > 0) {
          debugPrint('✅ Found sender.userId: $id');
          return id;
        }
      }
      if (senderMap.containsKey('user_id')) {
        final id = _parseInt(senderMap['user_id']);
        if (id > 0) {
          debugPrint('✅ Found sender.user_id: $id');
          return id;
        }
      }
    }
    
    // 6. Try from user object
    if (json.containsKey('user') && json['user'] is Map) {
      final userMap = json['user'] as Map;
      debugPrint('🔍 Checking user object: $userMap');
      
      if (userMap.containsKey('id')) {
        final id = _parseInt(userMap['id']);
        if (id > 0) {
          debugPrint('✅ Found user.id: $id');
          return id;
        }
      }
      if (userMap.containsKey('userId')) {
        final id = _parseInt(userMap['userId']);
        if (id > 0) {
          debugPrint('✅ Found user.userId: $id');
          return id;
        }
      }
    }
    
    // 7. Try parsing the entire JSON for any ID field
    for (final key in json.keys) {
      if (key.toLowerCase().contains('id') && json[key] != null) {
        final id = _parseInt(json[key]);
        if (id > 0) {
          debugPrint('✅ Found ID in field "$key": $id');
          return id;
        }
      }
    }
    
    // 8. Last resort: Check if the message has a sender object with any ID
    debugPrint('⚠️ Could not find sender ID in any field');
    debugPrint('📋 Available keys: ${json.keys}');
    debugPrint('📋 Full JSON: $json');
    
    return 0; // Return 0 as fallback
  }

  // ✅ IMPROVED: Parse sender object
  static Map<String, dynamic>? _parseSenderObject(Map<String, dynamic> json) {
    // Case 1: sender is already a complete object (API format)
    if (json.containsKey('sender') && json['sender'] is Map) {
      final senderMap = Map<String, dynamic>.from(json['sender'] as Map);
      if (senderMap.containsKey('id') || senderMap.containsKey('userId')) {
        debugPrint('✅ Found complete sender object');
        return senderMap;
      }
    }

    // Case 2: sender details are in root fields (WebSocket format)
    final senderId = _parseSenderId(json);
    if (senderId > 0) {
      final senderMap = <String, dynamic>{
        'id': senderId,
      };
      
      // Add any sender details found in root
      if (json.containsKey('senderName')) {
        senderMap['full_name'] = _parseString(json['senderName']);
      }
      if (json.containsKey('sender_name')) {
        senderMap['full_name'] = _parseString(json['sender_name']);
      }
      if (json.containsKey('senderUsername')) {
        senderMap['username'] = _parseString(json['senderUsername']);
      }
      if (json.containsKey('sender_username')) {
        senderMap['username'] = _parseString(json['sender_username']);
      }
      if (json.containsKey('senderProfilePicture')) {
        senderMap['profile_picture'] = _parseString(json['senderProfilePicture']);
      }
      if (json.containsKey('sender_profile_picture')) {
        senderMap['profile_picture'] = _parseString(json['sender_profile_picture']);
      }
      
      debugPrint('✅ Created sender object from root fields: $senderMap');
      return senderMap;
    }

    return null;
  }

  // Helper methods for safe parsing
  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) return value.toInt();
    return null;
  }

  static String _parseString(dynamic value) {
    if (value is String) return value;
    return value?.toString() ?? '';
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return true; // Default to true for isActive
  }

  static DateTime _parseDateTime(dynamic dateString) {
    if (dateString is String) {
      try {
        // Try parsing as RFC 1123 format (Tue, 14 Oct 2025 22:43:04 GMT)
        return HttpDate.parse(dateString);
      } catch (e) {
        try {
          // Fallback to ISO 8601 parsing
          return DateTime.parse(dateString);
        } catch (e) {
          debugPrint('❌ Failed to parse date: $dateString');
          return DateTime.now();
        }
      }
    }
    return DateTime.now();
  }

  static List<dynamic> _parseList(dynamic value) {
    if (value is List) return value;
    if (value is Map) return [value]; // Wrap single map in list
    return [];
  }

  static Map<String, dynamic>? _parseMap(dynamic value) {
    if (value is Map) {
      try {
        return value.cast<String, dynamic>();
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'group_chat_id': groupChatId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'attachments': attachments,
      'replied_to_id': repliedToId,
      'read_by': readBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive,
      'meta_data': metaData,
      'sender': sender,
      'replied_to': repliedTo,
    };
  }

  @override
  String toString() {
    return 'GroupMessage(id: $id, content: $content, senderId: $senderId)';
  }
}
