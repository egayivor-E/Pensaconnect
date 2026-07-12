import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pensaconnect/services/socketio_service.dart';
import '../models/group_chat_model.dart';
import '../services/api_service.dart';
import '../repositories/auth_repository.dart';
import '../models/group_member_model.dart';
import '../models/group_message_model.dart';
import '../models/bible_models.dart';

class GroupChatRepository {
  final Dio _dio;
  final AuthRepository authRepo;
  final SocketIoService _socketService;

  GroupChatRepository(this._dio, this.authRepo, this._socketService);

  Stream<List<GroupMessage>> watchMessages(int groupId) {
    return _socketService.watchMessages(groupId);
  }

  /// Fetch all groups the user belongs to
  Future<List<GroupChat>> getGroups() async {
    try {
      final response = await ApiService.get(
        'group-chats/',
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        debugPrint("✅ API Response: ${data['message']}");
        debugPrint("🔍 Status: ${data['status']}");

        if (data.containsKey('data') && data['data'] is List) {
          final List<dynamic> groupsList = data['data'];
          debugPrint("✅ Found ${groupsList.length} groups in 'data' field");

          return groupsList
              .map<GroupChat>((jsonItem) => GroupChat.fromJson(jsonItem))
              .toList();
        } else {
          debugPrint("⚠️ No 'data' field or 'data' is not a list");
          return [];
        }
      } else {
        debugPrint("❌ Failed to load groups: ${response.statusCode}");
        debugPrint("Response body: ${response.body}");
        throw Exception('Failed to load groups: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error fetching groups: $e");
      rethrow;
    }
  }

  /// Get messages for a specific group
  Future<List<GroupMessage>> getMessages(int groupId) async {
    try {
      final response = await ApiService.get(
        'group-chats/$groupId/messages',
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final dynamic decodedBody = json.decode(response.body);

        List<dynamic> messagesList;
        if (decodedBody is List) {
          messagesList = decodedBody;
        } else if (decodedBody is Map) {
          if (decodedBody.containsKey('data') && decodedBody['data'] is List) {
            messagesList = decodedBody['data'];
          } else if (decodedBody.containsKey('results') &&
              decodedBody['results'] is List) {
            messagesList = decodedBody['results'];
          } else if (decodedBody.containsKey('messages') &&
              decodedBody['messages'] is List) {
            messagesList = decodedBody['messages'];
          } else {
            messagesList = [];
          }
        } else {
          messagesList = [];
        }

        final messages = messagesList
            .map<GroupMessage>((jsonItem) => GroupMessage.fromJson(jsonItem))
            .toList();

        _socketService.setInitialMessages(groupId, messages);

        debugPrint("✅ Loaded ${messages.length} messages for group $groupId");
        return messages;
      } else {
        debugPrint("❌ Failed to load messages: ${response.statusCode}");
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error fetching messages: $e");
      rethrow;
    }
  }

  /// Get group details with members
  Future<GroupChat> getGroupDetails(int groupId) async {
    try {
      final response = await ApiService.get(
        'group-chats/$groupId',
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        Map<String, dynamic> groupData;
        if (data.containsKey('data') && data['data'] is Map) {
          groupData = data['data'];
        } else {
          groupData = data;
        }

        return GroupChat.fromJson(groupData);
      } else {
        debugPrint("❌ Failed to load group details: ${response.statusCode}");
        throw Exception('Failed to load group details: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error fetching group details: $e");
      rethrow;
    }
  }

  /// Create a new group chat
  Future<GroupChat> createGroup({
    required String name,
    required String description,
    String? avatar,
    bool isPublic = true,
    int maxMembers = 100,
    List<String> tags = const [],
  }) async {
    try {
      final response = await ApiService.post('group-chats/', {
        'name': name,
        'description': description,
        'avatar': avatar,
        'is_public': isPublic,
        'max_members': maxMembers,
        'tags': tags,
      }, headers: await _getHeaders());

      if (response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        return GroupChat.fromJson(data);
      } else {
        debugPrint("❌ Failed to create group: ${response.statusCode}");
        throw Exception('Failed to create group: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error creating group: $e");
      rethrow;
    }
  }

  /// Join a public group
  Future<void> joinGroup(int groupId) async {
    try {
      final response = await ApiService.post(
        'group-chats/$groupId/join',
        {},
        headers: await _getHeaders(),
      );

      if (response.statusCode != 200) {
        debugPrint("❌ Failed to join group: ${response.statusCode}");
        throw Exception('Failed to join group: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error joining group: $e");
      rethrow;
    }
  }

  /// Leave a group
  Future<void> leaveGroup(int groupId) async {
    try {
      final response = await ApiService.post(
        'group-chats/$groupId/leave',
        {},
        headers: await _getHeaders(),
      );

      if (response.statusCode != 200) {
        debugPrint("❌ Failed to leave group: ${response.statusCode}");
        throw Exception('Failed to leave group: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error leaving group: $e");
      rethrow;
    }
  }

  /// Send a message to a group
  Future<GroupMessage> sendMessage({
    required int groupId,
    required String content,
    String messageType = 'text',
    List<dynamic> attachments = const [],
    int? repliedToId,
  }) async {
    try {
      final response = await ApiService.post('group-chats/$groupId/messages', {
        'content': content,
        'message_type': messageType,
        'attachments': attachments,
        'replied_to_id': repliedToId,
      }, headers: await _getHeaders());

      if (response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        final message = GroupMessage.fromJson(data);

        // ✅ FIXED: Send COMPLETE message with ID and all fields via WebSocket
        _socketService.sendMessage(groupId, {
          'groupId': groupId,
          'id': message.id,                    // ✅ Include the REAL ID from database
          'content': message.content,
          'senderId': message.senderId,
          'messageType': message.messageType,
          'createdAt': message.createdAt.toIso8601String(),
          'sender': {
            'id': message.sender?['id'] ?? message.senderId,
            'username': message.sender?['username'] ?? 'Unknown',
            'full_name': message.sender?['full_name'] ?? 'Unknown User',
            'profile_picture': message.sender?['profile_picture'],
          }
        });

        debugPrint('✅ Message sent with real ID: ${message.id}');
        return message;
      } else {
        debugPrint("❌ Failed to send message: ${response.statusCode}");
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error sending message: $e");
      rethrow;
    }
  }

  /// Get group members
  Future<List<GroupMember>> getGroupMembers(int groupId) async {
    try {
      final response = await ApiService.get(
        'group-chats/$groupId/members',
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final dynamic decodedBody = json.decode(response.body);

        List<dynamic> membersList;
        if (decodedBody is List) {
          membersList = decodedBody;
        } else if (decodedBody is Map) {
          if (decodedBody.containsKey('data') && decodedBody['data'] is List) {
            membersList = decodedBody['data'];
          } else if (decodedBody.containsKey('results') &&
              decodedBody['results'] is List) {
            membersList = decodedBody['results'];
          } else if (decodedBody.containsKey('members') &&
              decodedBody['members'] is List) {
            membersList = decodedBody['members'];
          } else {
            membersList = [];
          }
        } else {
          membersList = [];
        }

        debugPrint("✅ Loaded ${membersList.length} members for group $groupId");
        return membersList
            .map<GroupMember>((jsonItem) => GroupMember.fromJson(jsonItem))
            .toList();
      } else {
        debugPrint("❌ Failed to load group members: ${response.statusCode}");
        throw Exception('Failed to load group members: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error fetching group members: $e");
      rethrow;
    }
  }

  /// Delete a group (admin only)
  Future<void> deleteGroup(int groupId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${_getBaseUrl()}/group-chats/$groupId'),
        headers: headers,
      );

      if (response.statusCode != 204) {
        debugPrint("❌ Failed to delete group: ${response.statusCode}");
        debugPrint("Response body: ${response.body}");
        throw Exception('Failed to delete group: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error deleting group: $e");
      rethrow;
    }
  }

  /// Update group information
  Future<GroupChat> updateGroup({
    required int groupId,
    String? name,
    String? description,
    String? avatar,
    bool? isPublic,
    int? maxMembers,
    List<String>? tags,
  }) async {
    try {
      final Map<String, dynamic> updateData = {};
      if (name != null) updateData['name'] = name;
      if (description != null) updateData['description'] = description;
      if (avatar != null) updateData['avatar'] = avatar;
      if (isPublic != null) updateData['is_public'] = isPublic;
      if (maxMembers != null) updateData['max_members'] = maxMembers;
      if (tags != null) updateData['tags'] = tags;

      final headers = await _getHeaders();
      final response = await http.patch(
        Uri.parse('${_getBaseUrl()}/group-chats/$groupId'),
        headers: headers,
        body: json.encode(updateData),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return GroupChat.fromJson(data);
      } else {
        debugPrint("❌ Failed to update group: ${response.statusCode}");
        debugPrint("Response body: ${response.body}");
        throw Exception('Failed to update group: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Error updating group: $e");
      rethrow;
    }
  }

  String _getBaseUrl() {
    return 'https://pensaconnect.onrender.com/api/v1';
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      final token = await authRepo.getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      debugPrint('⚠️ Could not get auth token: $e');
    }

    return headers;
  }
}
