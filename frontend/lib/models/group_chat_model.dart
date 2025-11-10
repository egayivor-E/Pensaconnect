import 'dart:convert'; // Add this import
import 'dart:io';
import 'package:flutter/material.dart';

import 'group_member_model.dart';
import 'group_message_model.dart';

class GroupChat {
  final int id;
  final String uuid;
  final String name;
  final String description;
  final String? avatar;
  final bool isPublic;
  final int maxMembers;
  final List<String> tags;
  final int createdById;
  final int memberCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final Map<String, dynamic>? metaData;

  // User who created the group
  final Map<String, dynamic>? createdBy;

  // Members (optional - for detailed view)
  final List<GroupMember>? members;

  GroupChat({
    required this.id,
    required this.uuid,
    required this.name,
    required this.description,
    this.avatar,
    required this.isPublic,
    required this.maxMembers,
    required this.tags,
    required this.createdById,
    required this.memberCount,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    this.metaData,
    this.createdBy,
    this.members,
  });

  factory GroupChat.fromJson(Map<String, dynamic> json) {
    return GroupChat(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      avatar: json['avatar'] as String?,
      isPublic: json['is_public'] as bool? ?? true,
      maxMembers: json['max_members'] as int? ?? 100,

      // FIXED: Handle tags which can be Map or List
      tags: _parseTags(json['tags']),

      createdById: json['created_by_id'] as int,
      memberCount: json['member_count'] as int? ?? 0,

      // FIXED: Use custom date parser
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),

      isActive: json['is_active'] as bool? ?? true,

      // FIXED: Handle meta_data which might be Map or null
      metaData: _parseMetaData(json['meta_data']),

      // FIXED: Handle created_by which might be Map or null
      createdBy: json['created_by'] is Map
          ? Map<String, dynamic>.from(json['created_by'] as Map)
          : null,

      members: json['members'] != null
          ? List<GroupMember>.from(
              (json['members'] as List).map(
                (x) => GroupMember.fromJson(x as Map<String, dynamic>),
              ),
            )
          : null,
    );
  }

  // Helper methods for safe parsing
  static List<String> _parseTags(dynamic tags) {
    if (tags is List) {
      return List<String>.from(tags);
    } else if (tags is Map) {
      // Convert map values to list of strings
      return tags.values.map((e) => e.toString()).toList();
    } else {
      return [];
    }
  }

  static Map<String, dynamic>? _parseMetaData(dynamic metaData) {
    if (metaData is Map) {
      return Map<String, dynamic>.from(metaData);
    }
    return null;
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
          debugPrint('Failed to parse date: $dateString');
          return DateTime.now();
        }
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'name': name,
      'description': description,
      'avatar': avatar,
      'is_public': isPublic,
      'max_members': maxMembers,
      'tags': tags,
      'created_by_id': createdById,
      'member_count': memberCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive,
      'meta_data': metaData,
      'created_by': createdBy,
      'members': members?.map((x) => x.toJson()).toList(),
    };
  }
}
