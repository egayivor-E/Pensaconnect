// lib/services/websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pensaconnect/models/group_message_model.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final Map<int, WebSocketChannel> _channels = {};
  final Map<int, StreamController<List<GroupMessage>>> _messageControllers = {};
  final String _baseUrl = 'ws://127.0.0.1:5000'; // Socket.IO server

  Stream<List<GroupMessage>> watchMessages(int groupId) {
    if (!_messageControllers.containsKey(groupId)) {
      _messageControllers[groupId] =
          StreamController<List<GroupMessage>>.broadcast();
      _connectToGroup(groupId);
    }
    return _messageControllers[groupId]!.stream;
  }

  void _connectToGroup(int groupId) async {
    try {
      _channels[groupId]?.sink.close();

      // ✅ Connect to main Socket.IO endpoint (not group-specific)
      final channel = WebSocketChannel.connect(Uri.parse(_baseUrl));

      _channels[groupId] = channel;

      // ✅ Send join event after connecting
      _sendJoinGroup(groupId);

      channel.stream.listen(
        (data) {
          _handleSocketIOMessage(data, groupId);
        },
        onError: (error) {
          _handleError(error, groupId);
        },
        onDone: () {
          _reconnect(groupId);
        },
      );

      debugPrint('🔌 WebSocket connected for group $groupId');
    } catch (e) {
      debugPrint('❌ WebSocket connection error: $e');
      _handleError(e, groupId);
    }
  }

  void _sendJoinGroup(int groupId) {
    try {
      // ✅ Socket.IO format: Send as JSON with event type
      final joinMessage = json.encode({
        'event': 'join_group',
        'data': {'groupId': groupId},
      });
      _channels[groupId]?.sink.add(joinMessage);
      debugPrint('👥 Sent join_group event for group $groupId');
    } catch (e) {
      debugPrint('Error sending join_group: $e');
    }
  }

  void _handleSocketIOMessage(dynamic data, int groupId) {
    try {
      debugPrint('📨 Raw WebSocket message: $data');

      final messageData = json.decode(data);
      final event = messageData['event'];
      final eventData = messageData['data'];

      switch (event) {
        case 'connected':
          debugPrint('✅ WebSocket connected: ${eventData['message']}');
          break;

        case 'joined_group':
          debugPrint('✅ Joined group: ${eventData['groupId']}');
          break;

        case 'message_received':
          debugPrint('💬 New message received via WebSocket');
          try {
            final message = GroupMessage.fromJson(eventData);
            _messageControllers[groupId]?.add([message]);
          } catch (e) {
            debugPrint('❌ Error parsing message: $e');
            _sendTestMessage(groupId, 'Parsed message from WebSocket');
          }
          break;

        case 'user_typing':
          debugPrint('⌨️ User typing: ${eventData['userId']}');
          break;

        default:
          debugPrint('📨 Unknown WebSocket event: $event');
          // Send test message for unknown events
          _sendTestMessage(groupId, 'Unknown event: $event');
      }
    } catch (e) {
      debugPrint('❌ Error parsing WebSocket message: $e');
      // Fallback: send test message
      _sendTestMessage(groupId, 'Fallback message - parsing error');
    }
  }

  void _sendTestMessage(int groupId, String content) {
    try {
      final testMessage = GroupMessage(
        id: DateTime.now().millisecondsSinceEpoch,
        uuid: 'ws-${DateTime.now().millisecondsSinceEpoch}',
        groupChatId: groupId,
        senderId: 0,
        content: content,
        messageType: 'text',
        attachments: [],
        readBy: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isActive: true,
        sender: {'full_name': 'System', 'username': 'system', 'id': 0},
      );
      _messageControllers[groupId]?.add([testMessage]);
    } catch (e) {
      debugPrint('Error creating test message: $e');
    }
  }

  void _handleError(dynamic error, int groupId) {
    debugPrint('❌ WebSocket error for group $groupId: $error');
  }

  void _reconnect(int groupId) {
    debugPrint('🔌 WebSocket disconnected, reconnecting in 5 seconds...');
    Future.delayed(const Duration(seconds: 5), () {
      _connectToGroup(groupId);
    });
  }

  Future<void> sendMessage(int groupId, String content) async {
    try {
      // ✅ Socket.IO format for sending messages
      final message = json.encode({
        'event': 'new_message',
        'data': {
          'groupId': groupId,
          'content': content,
          'senderId': 1, // You'll need to get actual user ID
        },
      });
      _channels[groupId]?.sink.add(message);
      debugPrint('📤 Sent message via WebSocket: $content');
    } catch (e) {
      debugPrint('❌ Error sending message via WebSocket: $e');
      rethrow;
    }
  }

  void disposeGroup(int groupId) {
    // ✅ Send leave event before disconnecting
    try {
      final leaveMessage = json.encode({
        'event': 'leave_group',
        'data': {'groupId': groupId},
      });
      _channels[groupId]?.sink.add(leaveMessage);
      debugPrint('👋 Sent leave_group event for group $groupId');
    } catch (e) {
      debugPrint('Error sending leave_group: $e');
    }

    _channels[groupId]?.sink.close();
    _messageControllers[groupId]?.close();
    _channels.remove(groupId);
    _messageControllers.remove(groupId);

    debugPrint('🔌 Disposed WebSocket for group $groupId');
  }
}
