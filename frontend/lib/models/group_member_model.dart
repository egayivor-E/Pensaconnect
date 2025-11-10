import 'dart:convert';
import 'dart:io';

class GroupMember {
  final int id;
  final int groupChatId;
  final int userId;
  final String groupRole; // 'admin', 'moderator', 'member'
  final DateTime joinedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final Map<String, dynamic>? metaData;

  // User details
  final Map<String, dynamic>? user;

  GroupMember({
    required this.id,
    required this.groupChatId,
    required this.userId,
    required this.groupRole,
    required this.joinedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    this.metaData,
    this.user,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: _parseInt(json['id']),
      groupChatId: _parseInt(json['group_chat_id']),
      userId: _parseInt(json['user_id']),
      groupRole: _parseString(json['group_role']),
      joinedAt: _parseDateTime(json['joined_at']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
      isActive: _parseBool(json['is_active']),
      metaData: _parseMap(json['meta_data']),
      user: _parseMap(json['user']),
    );
  }

  // Helper methods for safe parsing
  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
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
    return false;
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
      'group_chat_id': groupChatId,
      'user_id': userId,
      'group_role': groupRole,
      'joined_at': joinedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive,
      'meta_data': metaData,
      'user': user,
    };
  }

  @override
  String toString() {
    return 'GroupMember(id: $id, groupChatId: $groupChatId, userId: $userId, groupRole: $groupRole)';
  }
}
