import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';

class MessageRepository {
  /// ================================
  /// GROUP CHAT METHODS
  /// ================================

  /// Fetch messages from a group chat
  Future<List<Message>> fetchGroupMessages(String chatId) async {
    try {
      final response = await ApiService.get(
        'group-chats/$chatId/messages',
        headers: {},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data
            .map<Message>(
              (jsonItem) => Message.fromJson(jsonItem as Map<String, dynamic>),
            )
            .toList();
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
  Future<Message?> sendGroupMessage(String chatId, String content) async {
    try {
      final response = await ApiService.post('group-chats/$chatId/messages', {
        "content": content,
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        return Message.fromJson(json.decode(response.body));
      } else {
        debugPrint("❌ Failed to send group message: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error sending group message: $e");
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
        'private-chats/$userId/messages',
        headers: {},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data
            .map<Message>(
              (jsonItem) => Message.fromJson(jsonItem as Map<String, dynamic>),
            )
            .toList();
      } else {
        debugPrint(
          "❌ Failed to load private messages: ${response.statusCode} - ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error fetching private messages: $e");
      return [];
    }
  }

  /// Send a private message to another user
  Future<Message?> sendPrivateMessage(String userId, String content) async {
    try {
      final response = await ApiService.post('private-chats/$userId/messages', {
        "content": content,
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        return Message.fromJson(json.decode(response.body));
      } else {
        debugPrint("❌ Failed to send private message: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error sending private message: $e");
      return null;
    }
  }
}
