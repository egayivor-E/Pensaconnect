// lib/services/socketio_service.dart
import 'dart:async';
import 'package:pensaconnect/config/config.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'package:pensaconnect/models/group_message_model.dart';
import 'package:pensaconnect/services/auth_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketIoService {
  static final SocketIoService _instance = SocketIoService._internal();
  factory SocketIoService() => _instance;
  SocketIoService._internal();

  final Map<int, List<GroupMessage>> _messageCache = {};

  final Map<int, IO.Socket> _sockets = {};
  final Map<int, StreamController<List<GroupMessage>>> _messageControllers = {};
  final Map<int, StreamController<List<int>>> _typingControllers =
      {}; // userIds typing

  // ------------------ Public Streams ------------------

  Stream<List<GroupMessage>> watchMessages(int groupId) {
    if (!_messageControllers.containsKey(groupId)) {
      _messageControllers[groupId] =
          StreamController<List<GroupMessage>>.broadcast();
      _connectToGroup(groupId);
    }
    return _messageControllers[groupId]!.stream;
  }

  Stream<List<int>> watchTyping(int groupId) {
    if (!_typingControllers.containsKey(groupId)) {
      _typingControllers[groupId] = StreamController<List<int>>.broadcast();
    }
    return _typingControllers[groupId]!.stream;
  }

  // ------------------ Private Methods ------------------

  void _connectToGroup(int groupId) {
    try {
      debugPrint('🔌 Connecting Socket.IO for group $groupId...');

      _sockets[groupId]?.offAny();
      _sockets[groupId]?.disconnect();
      _sockets[groupId]?.destroy();

      final socket = IO.io(
        AppConfig.socketBaseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .setReconnectionAttempts(10)
            .setReconnectionDelay(3000)
            .build(),
      );

      _sockets[groupId] = socket;

      socket.onConnect((_) {
        debugPrint('✅ Connected to group $groupId');
        socket.emit('join_group', {'groupId': groupId});
      });

      socket.onDisconnect((_) {
        debugPrint('🔌 Disconnected from group $groupId');
      });

      socket.onError((error) {
        debugPrint('❌ Socket.IO error for group $groupId: $error');
      });

      socket.on('joined_group', (data) {
        debugPrint('✅ Joined group via Socket.IO: $data');
      });

      socket.on('message_received', (data) {
        try {
          final message = GroupMessage.fromJson(data);

          // Get current messages from cache
          final currentMessages = _messageCache[groupId] ?? [];

          // Append the new message
          final updatedMessages = List<GroupMessage>.from(currentMessages)
            ..add(message);

          // Update cache
          _messageCache[groupId] = updatedMessages;

          // Push to stream
          _messageControllers[groupId]?.add(updatedMessages);

          debugPrint(
            '💬 Message received for group $groupId: ${message.content}',
          );
        } catch (e) {
          debugPrint('❌ Failed to parse message: $e');
        }
      });

      socket.on('user_typing', (data) {
        final userId = data['userId'] as int;
        _updateTyping(groupId, userId, true);
      });

      socket.on('user_stop_typing', (data) {
        final userId = data['userId'] as int;
        _updateTyping(groupId, userId, false);
      });

      socket.on('message_read', (data) {
        final messageId = data['messageId'] as int;
        final userId = data['userId'] as int;
        _markMessageRead(groupId, messageId, userId);
      });

      socket.connect();
    } catch (e) {
      debugPrint('❌ Socket.IO connection failed: $e');
    }
  }

  final Map<int, List<int>> _typingUsers =
      {}; // groupId -> list of typing userIds

  void _updateTyping(int groupId, int userId, bool isTyping) {
    final updated = List<int>.from(_typingUsers[groupId] ?? []);

    if (isTyping) {
      if (!updated.contains(userId)) updated.add(userId);
    } else {
      updated.remove(userId);
    }

    _typingUsers[groupId] = updated;
    _typingControllers[groupId]?.add(updated);
  }

  void _markMessageRead(int groupId, int messageId, int userId) {
    // update your GroupMessage readBy list here if needed
    debugPrint('📖 Message $messageId read by user $userId');
  }

  // ------------------ Public Methods ------------------

  Future<void> sendMessage(
    int groupId,
    Map<String, dynamic> messageData,
  ) async {
    try {
      final socket = _sockets[groupId];
      if (socket != null && socket.connected) {
        socket.emit('new_message', messageData);
        debugPrint('📤 Sent message to group $groupId: $messageData');
      } else {
        debugPrint('⚠️ Socket not connected for group $groupId');
      }
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      rethrow;
    }
  }

  void sendTyping(int groupId, bool isTyping) {
    final socket = _sockets[groupId];
    if (socket != null && socket.connected) {
      final userId = AuthService().currentUser?['id'] ?? 0; // ✅ Use instance
      socket.emit(isTyping ? 'user_typing' : 'user_stop_typing', {
        'userId': userId,
        'groupId': groupId,
      });
    }
  }

  void markRead(int groupId, int messageId) {
    final socket = _sockets[groupId];
    if (socket != null && socket.connected) {
      final userId = AuthService().currentUser?['id'] ?? 0; // ✅ Use instance
      socket.emit('message_read', {
        'groupId': groupId,
        'messageId': messageId,
        'userId': userId,
      });
    }
  }

  void disposeGroup(int groupId) {
    final socket = _sockets[groupId];
    if (socket != null) {
      socket.emit('leave_group', {'groupId': groupId});
      socket.offAny();
      socket.disconnect();
      socket.destroy();
    }

    _sockets.remove(groupId);
    _messageControllers[groupId]?.close();
    _typingControllers[groupId]?.close();
    _messageControllers.remove(groupId);
    _typingControllers.remove(groupId);

    debugPrint('🔌 Disposed Socket.IO for group $groupId');
  }
}
