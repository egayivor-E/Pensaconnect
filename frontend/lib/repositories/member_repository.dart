// lib/repositories/member_repository.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/member.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class MemberRepository {
  /// Fetch members of a regular group
  Future<List<Member>> fetchGroupMembers(String groupId) async {
    try {
      final response = await ApiService.get(
        'messages/$groupId/members',
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          final List<dynamic> membersData = data['data'] ?? [];
          return membersData
              .map<Member>((jsonItem) => Member.fromJson(jsonItem))
              .toList();
        } else {
          debugPrint("❌ API returned error: ${data['message']}");
          return [];
        }
      } else {
        debugPrint("❌ Failed to load group members: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error fetching group members: $e");
      return [];
    }
  }

  /// Fetch members for live stream
  Future<List<Member>> fetchLiveMembers() async {
    try {
      debugPrint('🔄 Fetching live members from: live/messages/members');

      final response = await ApiService.get(
        'live/messages/members',
        headers: await _getAuthHeaders(),
      );

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📦 Raw response: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // ✅ TEMPORARY: Print the exact structure
        debugPrint('🎯 Full response structure:');
        debugPrint('  - status: ${data['status']}');
        debugPrint('  - message: ${data['message']}');
        if (data['data'] != null) {
          debugPrint('  - data type: ${data['data'].runtimeType}');
          if (data['data'] is List) {
            debugPrint('  - data length: ${data['data'].length}');
            for (int i = 0; i < data['data'].length; i++) {
              debugPrint('  - data[$i]: ${data['data'][i]}');
              debugPrint('  - data[$i] type: ${data['data'][i].runtimeType}');
            }
          }
        }

        if (data['status'] == 'success') {
          final List<dynamic> membersData = data['data'] ?? [];

          List<Member> members = [];
          for (var memberData in membersData) {
            try {
              final member = Member.fromJson(memberData);
              members.add(member);
              debugPrint('✅ Parsed member: ${member.toString()}');
            } catch (e) {
              debugPrint('❌ Error parsing member: $e');
              debugPrint('❌ Problematic data: $memberData');
            }
          }

          debugPrint('🎉 Successfully loaded ${members.length} members');
          return members;
        } else {
          debugPrint("❌ API error: ${data['message']}");
          return [];
        }
      } else {
        debugPrint("❌ HTTP error: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      debugPrint("❌ Exception fetching live members: $e");
      return [];
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }
}
