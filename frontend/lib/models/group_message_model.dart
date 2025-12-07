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

  // Add this additional factory constructor to your GroupMessage class
  factory GroupMessage.fromSocketIO(Map<String, dynamic> json) {
    debugPrint('🔌 Creating GroupMessage from Socket.IO data: $json');

    return GroupMessage(
      id: _parseInt(json['id']),
      uuid: '', // Socket.IO might not send UUID
      groupChatId: _parseInt(json['groupId']),
      senderId: _parseInt(json['sender']?['id']),
      content: _parseString(json['content']),
      messageType: _parseString(json['messageType']) ?? 'text',
      attachments: [], // Socket.IO might not send attachments
      repliedToId: null,
      readBy: _parseList(json['readBy']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['createdAt']), // Use same as createdAt
      isActive: true,
      sender: _parseMap(json['sender']),
    );
  }

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    debugPrint('🔍 Parsing GroupMessage from JSON (all formats)');

    // Parse sender ID - handle multiple possible field names
    final senderId = _parseSenderId(json);

    // Parse sender object - handle both formats
    final sender = _parseSender(json, senderId);

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

  static int _parseSenderId(Map<String, dynamic> json) {
    // Try multiple possible field names in order of priority
    if (json['sender_id'] != null) return _parseInt(json['sender_id']);
    if (json['senderId'] != null) return _parseInt(json['senderId']);
    if (json['sender'] != null && json['sender'] is Map) {
      return _parseInt(json['sender']['id']);
    }
    return 0;
  }

  static Map<String, dynamic>? _parseSender(
    Map<String, dynamic> json,
    int senderId,
  ) {
    // Case 1: sender is already a complete object (API format)
    if (json['sender'] is Map && json['sender'] != null) {
      final senderMap = Map<String, dynamic>.from(json['sender'] as Map);
      // Ensure it has required fields
      if (senderMap.containsKey('id')) {
        return senderMap;
      }
    }

    // Case 2: sender details are in root fields (WebSocket format)
    if (senderId > 0) {
      return {
        'id': senderId,
        'full_name': _parseString(
          json['senderName'] ?? json['sender_name'] ?? json['senderFullName'],
        ),
        'username': _parseString(
          json['senderUsername'] ?? json['sender_username'],
        ),
        'profile_picture': _parseString(
          json['senderProfilePicture'] ?? json['sender_profile_picture'],
        ),
      };
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
          print('Failed to parse date: $dateString');
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
