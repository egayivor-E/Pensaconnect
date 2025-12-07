import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart'; // Add this import

class MessageRepository {
  /// ================================
  /// GROUP CHAT METHODS
  /// ================================

  /// Fetch messages from a group chat
  Future<List<Message>> fetchGroupMessages(String groupId) async {
    try {
      final response = await ApiService.get(
        'messages/$groupId', // ← CORRECTED: matches your backend route
        headers: await _getAuthHeaders(), // ← ADD AUTH HEADERS
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // ✅ Handle your backend response format
        if (data['status'] == 'success') {
          final List<dynamic> messagesData = data['data'] ?? [];
          return messagesData
              .map<Message>(
                (jsonItem) =>
                    Message.fromJson(jsonItem as Map<String, dynamic>),
              )
              .toList();
        } else {
          debugPrint("❌ API returned error: ${data['message']}");
          return [];
        }
      } else {
        debugPrint(
          "❌ Failed to load group messages: ${response.statusCode} - ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error fetching group messages: $e");
      return [];
    }
  }

  /// Send a message to a group chat
  Future<Message?> sendGroupMessage(String groupId, String content) async {
    try {
      final response = await ApiService.post(
        'messages/$groupId', // ← CORRECTED: matches your backend route
        {"content": content},
        headers: await _getAuthHeaders(), // ← ADD AUTH HEADERS
      );

      // ✅ Handle your backend response format
      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          return Message.fromJson(data['data']);
        }
      }

      debugPrint("❌ Failed to send group message: ${response.body}");
      return null;
    } catch (e) {
      debugPrint("❌ Error sending group message: $e");
      return null;
    }
  }

  /// ================================
  /// LIVE CHAT METHODS (Alternative)
  /// ================================

  /// Fetch live stream messages (alternative endpoint)
  Future<List<Message>> fetchLiveMessages() async {
    try {
      final response = await ApiService.get(
        'live/messages/', // ← Uses the live_bp blueprint
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final List<dynamic> messagesData = data['data'] ?? [];
          return messagesData
              .map<Message>(
                (jsonItem) =>
                    Message.fromJson(jsonItem as Map<String, dynamic>),
              )
              .toList();
        }
      }

      debugPrint("❌ Failed to load live messages: ${response.body}");
      return [];
    } catch (e) {
      debugPrint("❌ Error fetching live messages: $e");
      return [];
    }
  }

  /// Send a live stream message (alternative endpoint)
  Future<Message?> sendLiveMessage(String content) async {
    try {
      final response = await ApiService.post(
        'live/messages/', // ← Uses the live_bp blueprint
        {"content": content},
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          return Message.fromJson(data['data']);
        }
      }

      debugPrint("❌ Failed to send live message: ${response.body}");
      return null;
    } catch (e) {
      debugPrint("❌ Error sending live message: $e");
      return null;
    }
  }

  /// ================================
  /// PRIVATE CHAT METHODS
  /// ================================

  /// Fetch messages in a private chat (with another user)
  Future<List<Message>> fetchPrivateMessages(String userId) async {
    try {
      final response = await ApiService.get(
        'private-chats/$userId/messages', // ← You'll need to implement this backend route
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final List<dynamic> messagesData = data['data'] ?? [];
          return messagesData
              .map<Message>(
                (jsonItem) =>
                    Message.fromJson(jsonItem as Map<String, dynamic>),
              )
              .toList();
        }
      }

      debugPrint(
        "❌ Failed to load private messages: ${response.statusCode} - ${response.body}",
      );
      return [];
    } catch (e) {
      debugPrint("❌ Error fetching private messages: $e");
      return [];
    }
  }

  /// Send a private message to another user
  Future<Message?> sendPrivateMessage(String userId, String content) async {
    try {
      final response = await ApiService.post(
        'private-chats/$userId/messages', // ← You'll need to implement this backend route
        {"content": content},
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          return Message.fromJson(data['data']);
        }
      }

      debugPrint("❌ Failed to send private message: ${response.body}");
      return null;
    } catch (e) {
      debugPrint("❌ Error sending private message: $e");
      return null;
    }
  }

  /// ================================
  /// HELPER METHODS
  /// ================================

  /// Get authentication headers with JWT token
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService().getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }
}
