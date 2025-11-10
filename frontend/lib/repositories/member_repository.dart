// lib/repositories/member_repository.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/member.dart';
import '../services/api_service.dart';

class MemberRepository {
  /// Fetch members of a group
  Future<List<Member>> fetchGroupMembers(String groupId) async {
    try {
      final response = await ApiService.get(
        'groups/$groupId/members',
        headers: {},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data
            .map<Member>(
              (jsonItem) => Member.fromJson(jsonItem as Map<String, dynamic>),
            )
            .toList();
      } else {
        debugPrint(
          "❌ Failed to load members: ${response.statusCode} - ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error fetching members: $e");
      return [];
    }
  }
}
