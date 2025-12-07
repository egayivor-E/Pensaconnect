// lib/services/socketio_service.dart
// ignore_for_file: unnecessary_null_comparison

import 'dart:async';
import 'package:pensaconnect/config/config.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/material.dart';
import 'package:pensaconnect/models/group_message_model.dart';
import 'package:pensaconnect/services/auth_service.dart';
import 'package:pensaconnect/models/user.dart';
import 'package:pensaconnect/providers/auth_provider.dart';

class SocketIoService {
  static final SocketIoService _instance = SocketIoService._internal();
  factory SocketIoService() => _instance;
  SocketIoService._internal();

  // ================================
  // PRIVATE PROPERTIES
  // ================================

  final Map<int, List<GroupMessage>> _messageCache = {};
  final Map<int, List<dynamic>> _memberCache = {};
  final Map<int, io.Socket> _sockets = {};
  final Map<int, StreamController<List<GroupMessage>>> _messageControllers = {};
  final Map<int, StreamController<List<dynamic>>> _memberControllers = {};
  final Map<int, StreamController<List<int>>> _typingControllers = {};
  final Map<int, List<int>> _typingUsers = {};

  // Connection management
  final Map<int, int> _connectionAttempts = {};
  final Map<int, Timer> _reconnectionTimers = {};
  final Map<int, Completer<bool>> _connectionCompleters = {};
  bool _isServiceInitialized = false;

  // ================================
  // INITIALIZATION
  // ================================

  Future<void> initialize() async {
    if (_isServiceInitialized) return;

    try {
      // Verify configuration
      if (Config.websocketUrl.isEmpty) {
        throw Exception('WebSocket URL not configured');
      }

      debugPrint(
        '🚀 SocketIoService initialized with URL: ${Config.websocketUrl}',
      );
      _isServiceInitialized = true;
    } catch (e) {
      debugPrint('❌ SocketIoService initialization failed: $e');
      rethrow;
    }
  }

  // ================================
  // PUBLIC STREAMS
  // ================================

  Stream<List<GroupMessage>> watchMessages(int groupId) {
    if (!_messageControllers.containsKey(groupId)) {
      _messageControllers[groupId] =
          StreamController<List<GroupMessage>>.broadcast();
      _connectToGroup(groupId);
    }
    return _messageControllers[groupId]!.stream;
  }

  // ✅ ADDED: Member stream
  Stream<List<dynamic>> watchGroupMembers(int groupId) {
    if (!_memberControllers.containsKey(groupId)) {
      _memberControllers[groupId] = StreamController<List<dynamic>>.broadcast();
      _connectToGroupMembers(groupId);
    }
    return _memberControllers[groupId]!.stream;
  }

  Stream<List<int>> watchTyping(int groupId) {
    if (!_typingControllers.containsKey(groupId)) {
      _typingControllers[groupId] = StreamController<List<int>>.broadcast();
    }
    return _typingControllers[groupId]!.stream;
  }

  // Connection status stream
  Stream<bool> watchConnectionStatus(int groupId) {
    final controller = StreamController<bool>.broadcast();

    // Initial status
    controller.add(_sockets[groupId]?.connected ?? false);

    // Listen for connection changes
    _sockets[groupId]?.onConnect((_) => controller.add(true));
    _sockets[groupId]?.onDisconnect((_) => controller.add(false));

    return controller.stream;
  }

  // ================================
  // CONNECTION MANAGEMENT
  // ================================

  Future<void> _connectToGroup(int groupId) async {
    if (!Config.enableLiveChat) return;

    try {
      debugPrint('🔌 Connecting Socket.IO for group $groupId...');

      // Cleanup any previous connection
      _cleanupGroupConnection(groupId);

      // Create socket
      final options = io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setReconnectionAttempts(Config.maxConnectionRetries)
          .setReconnectionDelay(Config.connectionRetryDelay * 1000)
          .setTimeout(30000)
          .build();

      final socket = io.io(Config.websocketUrl, options);

      // Attach auth token
      final token = await AuthService().getToken();
      if (token != null && token.isNotEmpty) {
        socket.io.options?['query'] = {'token': token};
        debugPrint('🔑 Auth token attached for Socket.IO');
      }

      _sockets[groupId] = socket;
      _connectionAttempts[groupId] = 0;
      _connectionCompleters[groupId] = Completer<bool>();

      // ======== CONNECTION EVENTS ========
      socket.onConnect((_) {
        debugPrint('✅ Socket.IO Connected for group $groupId');

        // Complete connection
        if (!_connectionCompleters[groupId]!.isCompleted) {
          _connectionCompleters[groupId]!.complete(true);
        }

        // Auto join group room
        socket.emit('join_group', {'groupId': groupId});
      });

      socket.onConnectError((error) {
        debugPrint('❌ Connection error for group $groupId: $error');
        _handleConnectionError(groupId, error.toString());
        if (!_connectionCompleters[groupId]!.isCompleted) {
          _connectionCompleters[groupId]!.complete(false);
        }
      });

      socket.onDisconnect((_) {
        debugPrint('🔌 Disconnected from group $groupId');
        _handleDisconnection(groupId);
      });

      socket.onReconnect((_) {
        debugPrint('🔄 Reconnected to group $groupId');
      });

      socket.onReconnectAttempt((attempt) {
        debugPrint('🔄 Reconnection attempt $attempt for group $groupId');
        _connectionAttempts[groupId] = attempt;
      });

      socket.onError((error) {
        debugPrint('❌ Socket.IO error: $error');
      });

      // ======== SERVER EVENTS ========
      socket.on('joined', (data) {
        debugPrint('✅ Joined group room: $data');
        _connectToGroupMembers(groupId); // Init members stream
      });

      socket.on('new_message', (data) {
        debugPrint('📨 Received new_message event');

        try {
          if (data is Map<String, dynamic>) {
            final message = GroupMessage.fromJson(data);
            debugPrint(
              '✅ Parsed message - ID: ${message.id}, Sender: ${message.senderId}, Content: ${message.content}',
            );
            _handleIncomingMessage(groupId, message);
          } else {
            debugPrint('❌ WebSocket data is not a Map<String, dynamic>');
          }
        } catch (e, stackTrace) {
          debugPrint('❌ Failed to parse message: $e');
          debugPrint('❌ Stack trace: $stackTrace');
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

      socket.on('members_updated', (data) {
        try {
          if (data['groupId'] == groupId) {
            final members = List<dynamic>.from(data['members'] ?? []);
            _handleMemberUpdates(groupId, members);
          }
        } catch (e) {
          debugPrint('❌ Members update error: $e');
        }
      });

      socket.on('connected', (data) {
        debugPrint('🔌 Connected event received: $data');
        // Handle connection event
        if (data is Map && data['status'] == 'success') {
          debugPrint('✅ WebSocket connection successful');
          debugPrint('📌 Assigned SID: ${data['sid']}');
        }
      });

      // ======== CONNECT ========
      socket.connect();
    } catch (e) {
      debugPrint('❌ Socket.IO setup failed: $e');
      _logError('connection_setup', e, groupId: groupId);
    }
  }

  // ✅ ADDED: Wait for connection method
  Future<bool> waitForConnection(int groupId, {int timeoutSeconds = 10}) async {
    final socket = _sockets[groupId];
    if (socket == null) {
      debugPrint('❌ No socket found for group $groupId');
      return false;
    }

    // If already connected, return immediately
    if (socket.connected) {
      return true;
    }

    // Use existing completer or create new one
    if (_connectionCompleters[groupId] == null) {
      _connectionCompleters[groupId] = Completer<bool>();
    }

    // Set up timeout
    final completer = _connectionCompleters[groupId]!;
    final timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) {
        debugPrint('⏰ Connection timeout for group $groupId');
        completer.complete(false);
      }
    });

    try {
      final result = await completer.future;
      timer.cancel();
      return result;
    } catch (e) {
      timer.cancel();
      debugPrint('❌ Error waiting for connection: $e');
      return false;
    }
  }

  // ✅ ADDED: Member connection management
  void _connectToGroupMembers(int groupId) {
    final socket = _sockets[groupId];
    if (socket == null || !socket.connected) return;

    // Listen for updated members list
    socket.on('members_updated', (data) {
      try {
        if (data is Map && data['groupId'] == groupId) {
          final members = List<dynamic>.from(data['members'] ?? []);
          _handleMemberUpdates(groupId, members);
        }
      } catch (e) {
        debugPrint('❌ Error handling members_updated: $e');
        _logError('members_update', e, groupId: groupId);
      }
    });

    // Individual user join
    socket.on('user_joined', (data) {
      try {
        if (data is Map && data['groupId'] == groupId) {
          debugPrint('👤 User joined group $groupId: $data');
          _requestMemberList(groupId); // always refresh members
        }
      } catch (e) {
        debugPrint('❌ Error handling user_joined: $e');
      }
    });

    // Individual user leave
    socket.on('user_left', (data) {
      try {
        if (data is Map && data['groupId'] == groupId) {
          debugPrint('👤 User left group $groupId: $data');
          _requestMemberList(groupId);
        }
      } catch (e) {
        debugPrint('❌ Error handling user_left: $e');
      }
    });

    // Request initial members
    _requestMemberList(groupId);
  }

  // ✅ ADDED: Member list management
  void _requestMemberList(int groupId) {
    final socket = _sockets[groupId];
    if (socket != null && socket.connected) {
      socket.emit('get_members', {'groupId': groupId});
      debugPrint('📋 Requested member list for group $groupId');
    }
  }

  void _handleMemberUpdates(int groupId, List<dynamic> members) {
    try {
      // Update cache
      _memberCache[groupId] = members;

      // Push to stream
      _memberControllers[groupId]?.add(members);

      debugPrint('👥 Members updated for group $groupId: ${members.length}');
    } catch (e) {
      debugPrint('❌ Error handling member updates: $e');
      _logError('member_updates', e, groupId: groupId);
    }
  }
  // ================================
  // MESSAGE HANDLING
  // ================================

  void _handleIncomingMessage(int groupId, GroupMessage message) {
    try {
      // ✅ FIXED: Improved message validation
      if (!_isValidMessage(message)) {
        debugPrint('⚠️ Invalid message received, ignoring: ${message.id}');
        debugPrint(
          '⚠️ Message details: content="${message.content}", senderId=${message.senderId}, createdAt=${message.createdAt}',
        );
        return;
      }

      // Get current messages from cache
      final currentMessages = _messageCache[groupId] ?? [];

      // Check for duplicates
      if (currentMessages.any((m) => m.id == message.id)) {
        debugPrint('⚠️ Duplicate message received: ${message.id}');
        return;
      }

      // Append the new message
      final updatedMessages = List<GroupMessage>.from(currentMessages)
        ..add(message);

      // Update cache (limit size for memory management)
      if (updatedMessages.length > 1000) {
        updatedMessages.removeRange(0, 200); // Keep last 800 messages
      }
      _messageCache[groupId] = updatedMessages;

      // Push to stream
      _messageControllers[groupId]?.add(updatedMessages);

      debugPrint(
        '💬 Message received for group $groupId: ${message.content} (${message.createdAt})',
      );
    } catch (e) {
      debugPrint('❌ Error handling incoming message: $e');
      _logError('message_handling', e, groupId: groupId);
    }
  }

  bool _isValidMessage(GroupMessage message) {
    // ✅ FIXED: More flexible validation
    return message.id != null &&
        message.id != 0 &&
        message.content.isNotEmpty &&
        message.senderId != null &&
        message.senderId != 0 &&
        message.createdAt != null;
  }

  // ================================
  // MESSAGE READ HANDLING
  // ================================

  void _handleMessageRead(int groupId, int messageId, int userId) {
    try {
      debugPrint(
        '📖 Message $messageId read by user $userId in group $groupId',
      );

      // Update local cache to mark message as read
      final messages = _messageCache[groupId];
      if (messages != null) {
        final messageIndex = messages.indexWhere((m) => m.id == messageId);
        if (messageIndex != -1) {
          final message = messages[messageIndex];
          final updatedReadBy = List<dynamic>.from(message.readBy);

          if (!updatedReadBy.contains(userId)) {
            updatedReadBy.add(userId);
            debugPrint('✅ User $userId read message $messageId');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling message read: $e');
      _logError('message_read', e, groupId: groupId);
    }
  }

  // ================================
  // TYPING INDICATORS
  // ================================

  void _updateTyping(int groupId, int userId, bool isTyping) {
    try {
      final updated = List<int>.from(_typingUsers[groupId] ?? []);

      if (isTyping) {
        if (!updated.contains(userId)) {
          updated.add(userId);

          // Auto-remove after 3 seconds if still typing
          Timer(const Duration(seconds: 3), () {
            if (_typingUsers[groupId]?.contains(userId) == true) {
              _updateTyping(groupId, userId, false);
            }
          });
        }
      } else {
        updated.remove(userId);
      }

      _typingUsers[groupId] = updated;
      _typingControllers[groupId]?.add(updated);

      debugPrint('💬 Typing update for group $groupId: $updated');
    } catch (e) {
      debugPrint('❌ Error updating typing indicator: $e');
    }
  }

  // ================================
  // ERROR HANDLING & RECONNECTION
  // ================================

  void _handleDisconnection(int groupId) {
    _typingUsers[groupId]?.clear();
    _typingControllers[groupId]?.add([]);

    // Reset connection completer
    _connectionCompleters.remove(groupId);

    // Schedule reconnection if needed
    if (_connectionAttempts[groupId]! < Config.maxConnectionRetries) {
      _scheduleReconnection(groupId);
    }
  }

  void _handleConnectionError(int groupId, String error) {
    _connectionAttempts[groupId] = (_connectionAttempts[groupId] ?? 0) + 1;

    // Complete connection promise with failure
    if (_connectionCompleters[groupId] != null &&
        !_connectionCompleters[groupId]!.isCompleted) {
      _connectionCompleters[groupId]!.complete(false);
    }

    if (_connectionAttempts[groupId]! >= Config.maxConnectionRetries) {
      debugPrint('❌ Max connection attempts reached for group $groupId');
      _messageControllers[groupId]?.addError(
        'Connection failed after ${Config.maxConnectionRetries} attempts',
      );
    } else {
      _scheduleReconnection(groupId);
    }
  }

  void _scheduleReconnection(int groupId) {
    _reconnectionTimers[groupId]?.cancel();

    _reconnectionTimers[groupId] = Timer(
      Duration(seconds: Config.connectionRetryDelay),
      () {
        debugPrint('🔄 Attempting to reconnect to group $groupId...');
        _connectToGroup(groupId);
      },
    );
  }

  void _handleMessageRejection(dynamic data) {
    debugPrint('Message rejected by moderation: $data');
  }

  void _handleUserBan(dynamic data) {
    debugPrint('User banned from chat: $data');
  }

  // ================================
  // PUBLIC METHODS
  // ================================

  // =================== SEND MESSAGE ===================

  Future<void> sendMessage(
    int groupId,
    Map<String, dynamic> messageData,
  ) async {
    final socket = _sockets[groupId];
    if (socket == null)
      // ignore: curly_braces_in_flow_control_structures
      throw Exception('Socket not initialized for group $groupId');

    // Wait for connection
    if (!socket.connected) {
      final connected = await waitForConnection(groupId);
      if (!connected)
        throw Exception('Socket connection timeout for group $groupId');
    }

    final user = AuthService().currentUser;
    final userId = user?['id'];
    if (userId == null) throw Exception('User not authenticated');

    final enhancedMessage = Map<String, dynamic>.from(messageData)
      ..addAll({
        'senderId': userId,
        'sentAt': DateTime.now().toIso8601String(),
        'clientId': 'flutter_${DateTime.now().millisecondsSinceEpoch}',
      });

    socket.emit('send_message', enhancedMessage);
    debugPrint(
      '📤 Sent message to group $groupId: ${enhancedMessage['content']}',
    );
  }

  void sendTyping(int groupId, bool isTyping) {
    if (!Config.enableLiveChat) return;

    final socket = _sockets[groupId];
    if (socket == null || !socket.connected) {
      debugPrint(
        '⏳ Socket not connected, skipping typing indicator for group $groupId',
      );
      return;
    }

    final userId = AuthService().currentUser?['id'] ?? 0;
    if (userId == 0) {
      debugPrint('⚠️ User ID not available for typing indicator');
      return;
    }

    // Emit the correct event based on typing state
    final event = isTyping ? 'user_typing' : 'user_stop_typing';
    socket.emit(event, {
      'userId': userId,
      'groupId': groupId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint(
      '💬 Sent typing event [$event] for user $userId in group $groupId',
    );
  }

  void markRead(int groupId, int messageId) {
    final socket = _sockets[groupId];
    if (socket != null && socket.connected) {
      final userId = AuthService().currentUser?['id'] ?? 0;
      if (userId == 0) {
        debugPrint('⚠️ User ID not available for mark read');
        return;
      }

      socket.emit('message_read', {
        'groupId': groupId,
        'messageId': messageId,
        'userId': userId,
        'readAt': DateTime.now().toIso8601String(),
      });
    }
  }

  // ✅ ADDED: Connection debug method
  void debugConnectionStatus(int groupId) {
    final socket = _sockets[groupId];
    debugPrint('🔍 Socket.IO Debug for group $groupId:');
    debugPrint('   - Socket exists: ${socket != null}');
    debugPrint('   - Connected: ${socket?.connected ?? false}');
    debugPrint('   - ID: ${socket?.id}');
    debugPrint('   - Connection attempts: ${_connectionAttempts[groupId]}');
    debugPrint('   - WebSocket URL: ${Config.websocketUrl}');
    debugPrint('   - Live Chat Enabled: ${Config.enableLiveChat}');

    final user = AuthService().currentUser;
    debugPrint('   - User ID: ${user?['id']}');
    debugPrint('   - Username: ${user?['username']}');
  }

  // ✅ ADDED: Member utility methods
  List<dynamic> getCachedMembers(int groupId) {
    return _memberCache[groupId] ?? [];
  }

  int getMemberCount(int groupId) {
    return _memberCache[groupId]?.length ?? 0;
  }

  // ================================
  // CONNECTION STATUS & UTILITIES
  // ================================

  bool isConnected(int groupId) {
    return _sockets[groupId]?.connected ?? false;
  }

  int getConnectionAttempts(int groupId) {
    return _connectionAttempts[groupId] ?? 0;
  }

  // ================================
  // CLEANUP
  // ================================

  void _cleanupGroupConnection(int groupId) {
    _sockets[groupId]?.offAny();
    _sockets[groupId]?.disconnect();
    _sockets[groupId]?.destroy();
    _reconnectionTimers[groupId]?.cancel();
    _connectionCompleters.remove(groupId);
  }

  // ✅ ADDED: Member cleanup
  void disposeGroupMembers(int groupId) {
    _memberControllers[groupId]?.close();
    _memberControllers.remove(groupId);
    _memberCache.remove(groupId);
  }

  void disposeGroup(int groupId) {
    debugPrint('🔌 Disposing Socket.IO for group $groupId');

    // Leave group
    final user = AuthService().currentUser;
    final userId = user?['id'];

    if (userId != null) {
      _sockets[groupId]?.emit('leave_group', {
        'groupId': groupId,
        'userId': userId,
      });
    }

    _cleanupGroupConnection(groupId);

    // Clean up resources
    _sockets.remove(groupId);
    _messageControllers[groupId]?.close();
    _typingControllers[groupId]?.close();
    _memberControllers[groupId]?.close();
    _messageControllers.remove(groupId);
    _typingControllers.remove(groupId);
    _memberControllers.remove(groupId);
    _typingUsers.remove(groupId);
    _connectionAttempts.remove(groupId);
    _reconnectionTimers.remove(groupId);
    _memberCache.remove(groupId);
    _connectionCompleters.remove(groupId);
  }

  void disposeAll() {
    debugPrint('🔌 Disposing all Socket.IO connections');

    for (final groupId in _sockets.keys.toList()) {
      disposeGroup(groupId);
    }

    _messageCache.clear();
    _memberCache.clear();
    _isServiceInitialized = false;
  }

  // ================================
  // ERROR LOGGING
  // ================================

  void _logError(String type, dynamic error, {int? groupId}) {
    final errorInfo = {
      'type': type,
      'error': error.toString(),
      'groupId': groupId,
      'timestamp': DateTime.now().toIso8601String(),
      'connected': groupId != null ? isConnected(groupId) : null,
    };

    debugPrint('🔴 Socket Error: $errorInfo');
  }
}
