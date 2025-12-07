// lib/models/member.dart
import 'package:flutter/foundation.dart';

class Member {
  final String id;
  final String name;
  final String? profileImage;
  final bool isOnline;
  final String? lastSeen;

  Member({
    required this.id,
    required this.name,
    this.profileImage,
    this.isOnline = false,
    this.lastSeen,
  });

  factory Member.fromJson(dynamic json) {
    try {
      Map<String, dynamic> data;
      if (json is Map<String, dynamic>) {
        data = json;
      } else if (json is Map) {
        data = Map<String, dynamic>.from(json);
      } else {
        debugPrint('❌ Invalid JSON type for Member: ${json.runtimeType}');
        data = {};
      }

      // ✅ USE THE ACTUAL FIELD NAMES FROM YOUR BACKEND
      return Member(
        id: data['id']?.toString() ?? '0', // Convert int to string
        name:
            data['username']?.toString() ??
            data['full_name']?.toString() ??
            'Unknown User',
        profileImage: data['profile_picture']?.toString(),
        isOnline: data['is_online'] == true,
        lastSeen: data['last_seen']?.toString(),
      );
    } catch (e) {
      debugPrint('❌ Error parsing Member JSON: $e');
      debugPrint('❌ JSON data: $json');
      return Member(id: '0', name: 'Unknown User', isOnline: false);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (profileImage != null) 'profileImage': profileImage,
      'isOnline': isOnline,
      if (lastSeen != null) 'lastSeen': lastSeen,
    };
  }

  @override
  String toString() {
    return 'Member(id: $id, name: $name, isOnline: $isOnline, profileImage: $profileImage)';
  }
}
