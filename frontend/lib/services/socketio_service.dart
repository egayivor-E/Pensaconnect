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
  final Map<int, Set<int>> _messageIds = {};
  final Map<int, Set<String>> _messageContentHashes = {};
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

      _messageIds[groupId] = <int>{};
      _messageContentHashes[groupId] = <String>{};

      if (_messageCache.containsKey(groupId)) {
        final cached = _messageCache[groupId]!;
        if (cached.isNotEmpty) {
          debugPrint(
            '📦 Delivering ${cached.length} cached messages for group $groupId',
          );
          _messageControllers[groupId]!.add(cached);
        }
      }

      _connectToGroup(groupId);
    }
    return _messageControllers[groupId]!.stream;
  }

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

  Stream<bool> watchConnectionStatus(int groupId) {
    final controller = StreamController<bool>.broadcast();
    controller.add(_sockets[groupId]?.connected ?? false);
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

      _cleanupGroupConnection(groupId);

      final token = await AuthService().getToken();

      final options = io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setPath('/socket.io')
          .setExtraHeaders(
            token != null && token.isNotEmpty
                ? {'Authorization': 'Bearer $token'}
                : {},
          )
          .setQuery({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(30000)
          .disableAutoConnect()
          .build();

      final socket = io.io(Config.websocketUrl, options);
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

        _messageIds[groupId] = <int>{};
        _messageContentHashes[groupId] = <String>{};

        if (!_connectionCompleters[groupId]!.isCompleted) {
          _connectionCompleters[groupId]!.complete(true);
        }
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
        _connectToGroupMembers(groupId);
      });

      socket.on('new_message', (data) {
        debugPrint('📨 Received new_message event');

        try {
          if (data is Map<String, dynamic>) {
            final isHistorical =
                data['historical'] == true || data['is_historical'] == true;

            if (isHistorical) {
              debugPrint(
                '📜 Historical message received - already loaded via HTTP, skipping',
              );
              return;
            }

            final message = GroupMessage.fromJson(data);

            debugPrint(
              '📩 Message from user ${message.senderId}: "${message.content}" (ID: ${message.id})',
            );

            if (_messageIds[groupId]?.contains(message.id) == true) {
              debugPrint('🔄 Duplicate message ${message.id} ignored');
              return;
            }

            final contentHash = _generateContentHash(message);
            if (_messageContentHashes[groupId]?.contains(contentHash) == true) {
              debugPrint('🔄 Duplicate message by content hash, skipping');
              return;
            }

            debugPrint(
              '✅ Parsed new message - ID: ${message.id}, Sender: ${message.senderId}, Content: ${message.content}',
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
        if (data is Map && data['status'] == 'success') {
          debugPrint('✅ WebSocket connection successful');
          debugPrint('📌 Assigned SID: ${data['sid']}');
        }
      });

      socket.connect();
    } catch (e) {
      debugPrint('❌ Socket.IO setup failed: $e');
      _logError('connection_setup', e, groupId: groupId);
    }
  }

  Future<bool> waitForConnection(int groupId, {int timeoutSeconds = 10}) async {
    final socket = _sockets[groupId];
    if (socket == null) {
      debugPrint('❌ No socket found for group $groupId');
      return false;
    }

    if (socket.connected) {
      return true;
    }

    if (_connectionCompleters[groupId] == null) {
      _connectionCompleters[groupId] = Completer<bool>();
    }

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

  void _connectToGroupMembers(int groupId) {
    final socket = _sockets[groupId];
    if (socket == null || !socket.connected) return;

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

    socket.on('user_joined', (data) {
      try {
        if (data is Map && data['groupId'] == groupId) {
          debugPrint('👤 User joined group $groupId: $data');
          _requestMemberList(groupId);
        }
      } catch (e) {
        debugPrint('❌ Error handling user_joined: $e');
      }
    });

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

    _requestMemberList(groupId);
  }

  void _requestMemberList(int groupId) {
    final socket = _sockets[groupId];
    if (socket != null && socket.connected) {
      socket.emit('get_members', {'groupId': groupId});
      debugPrint('📋 Requested member list for group $groupId');
    }
  }

  void _handleMemberUpdates(int groupId, List<dynamic> members) {
    try {
      _memberCache[groupId] = members;
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

  String _generateContentHash(GroupMessage message) {
    return '${message.senderId}:${message.content}:${message.createdAt.millisecondsSinceEpoch ~/ 10000}';
  }

  void _handleIncomingMessage(int groupId, GroupMessage message) {
    try {
      if (!_isValidMessage(message)) {
        debugPrint('⚠️ Invalid message received, ignoring: ${message.id}');
        return;
      }

      if (_messageIds[groupId]?.contains(message.id) == true) {
        debugPrint('🔄 Duplicate message ${message.id} already exists, skipping');
        return;
      }

      final contentHash = _generateContentHash(message);
      if (_messageContentHashes[groupId]?.contains(contentHash) == true) {
        debugPrint('🔄 Duplicate message by content hash, skipping');
        return;
      }

      final currentMessages = _messageCache[groupId] ?? [];
      final updatedMessages = List<GroupMessage>.from(currentMessages)..add(message);
      updatedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      _messageCache[groupId] = updatedMessages;
      _messageIds[groupId]?.add(message.id);
      _messageContentHashes[groupId]?.add(contentHash);

      final controller = _messageControllers[groupId];
      if (controller != null && !controller.isClosed) {
        controller.add(updatedMessages);
        debugPrint(
          '💬 New message delivered to group $groupId: ${message.content} (from user ${message.senderId})',
        );
      }
    } catch (e) {
      debugPrint('❌ Error handling incoming message: $e');
      _logError('message_handling', e, groupId: groupId);
    }
  }

  bool _isValidMessage(GroupMessage message) {
    if (message.id == null || message.id == 0) {
      return message.content.isNotEmpty &&
          message.senderId != null &&
          message.senderId != 0 &&
          message.createdAt != null;
    }
    return message.id != null &&
        message.id != 0 &&
        message.content.isNotEmpty &&
        message.senderId != null &&
        message.senderId != 0 &&
        message.createdAt != null;
  }

  // ================================
  // CACHE MANAGEMENT
  // ================================

  void setInitialMessages(int groupId, List<GroupMessage> messages) {
    final messageIds = _messageIds[groupId] ?? <int>{};
    final contentHashes = _messageContentHashes[groupId] ?? <String>{};

    for (final msg in messages) {
      messageIds.add(msg.id);
      contentHashes.add(_generateContentHash(msg));
    }
    _messageIds[groupId] = messageIds;
    _messageContentHashes[groupId] = contentHashes;

    _messageCache[groupId] = List.from(messages);
    _messageCache[groupId]?.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    debugPrint(
      '📦 Set initial ${messages.length} messages for group $groupId (${messageIds.length} IDs, ${contentHashes.length} hashes tracked)',
    );

    final controller = _messageControllers[groupId];
    if (controller != null && !controller.isClosed) {
      controller.add(_messageCache[groupId]!);
    }
  }

  List<GroupMessage>? getCachedMessages(int groupId) {
    return _messageCache[groupId];
  }

  // ================================
  // MESSAGE READ HANDLING
  // ================================

  void _handleMessageRead(int groupId, int messageId, int userId) {
    try {
      debugPrint('📖 Message $messageId read by user $userId in group $groupId');
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
    _connectionCompleters.remove(groupId);

    if (_connectionAttempts[groupId]! < Config.maxConnectionRetries) {
      _scheduleReconnection(groupId);
    }
  }

  void _handleConnectionError(int groupId, String error) {
    _connectionAttempts[groupId] = (_connectionAttempts[groupId] ?? 0) + 1;

    if (_connectionCompleters[groupId] != null &&
        !_connectionCompleters[groupId]!.isCompleted) {
      _connectionCompleters[groupId]!.complete(false);
    }

    if (_connectionAttempts[groupId]! >= Config.maxConnectionRetries) {
      debugPrint('❌ Max connection attempts reached for group $groupId');
      _messageControllers[groupId]?.addError(
        'Connection failed after ${Config.maxConnectionRetries} attempts',
      );
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
  // PUBLIC METHODS - FIXED WITH PROPER USER ID
  // ================================

  Future<void> sendMessage(
    int groupId,
    Map<String, dynamic> messageData,
  ) async {
    final socket = _sockets[groupId];
    if (socket == null)
      throw Exception('Socket not initialized for group $groupId');

    if (!socket.connected) {
      final connected = await waitForConnection(groupId);
      if (!connected)
        throw Exception('Socket connection timeout for group $groupId');
    }

    // ✅ FIXED: Get user from AuthService
    final user = AuthService().currentUser;
    final userId = user?['id'];
    
    // ✅ If user is null, try to get from AuthProvider
    if (userId == null) {
      try {
        final authProvider = AuthProvider();
        final currentUser = authProvider.currentUser;
        if (currentUser != null) {
          final userData = currentUser.toJson();
          final enhancedMessage = Map<String, dynamic>.from(messageData)
            ..addAll({
              'senderId': userData['id'],
              'sentAt': DateTime.now().toIso8601String(),
              'clientId': 'flutter_${DateTime.now().millisecondsSinceEpoch}',
              'sender': {
                'id': userData['id'],
                'username': userData['username'] ?? 'unknown',
                'full_name': userData['full_name'] ?? 'Unknown User',
                'profile_picture': userData['profile_picture'],
              }
            });
          socket.emit('send_message', enhancedMessage);
          debugPrint('📤 Sent message to group $groupId with user ID: ${userData['id']}');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Could not get user from AuthProvider: $e');
      }
      throw Exception('User not authenticated - cannot send message');
    }

    final enhancedMessage = Map<String, dynamic>.from(messageData)
      ..addAll({
        'senderId': userId,
        'sentAt': DateTime.now().toIso8601String(),
        'clientId': 'flutter_${DateTime.now().millisecondsSinceEpoch}',
        'sender': {
          'id': userId,
          'username': user?['username'] ?? 'unknown',
          'full_name': user?['full_name'] ?? 'Unknown User',
          'profile_picture': user?['profile_picture'],
        }
      });

    socket.emit('send_message', enhancedMessage);
    debugPrint('📤 Sent message to group $groupId with user ID: $userId');
  }

  void sendTyping(int groupId, bool isTyping) {
    if (!Config.enableLiveChat) return;

    final socket = _sockets[groupId];
    if (socket == null || !socket.connected) {
      debugPrint('⏳ Socket not connected, skipping typing indicator for group $groupId');
      return;
    }

    // ✅ FIXED: Get user from AuthService
    final user = AuthService().currentUser;
    final userId = user?['id'];
    
    // ✅ If user is null, try AuthProvider
    if (userId == null) {
      try {
        final authProvider = AuthProvider();
        final currentUser = authProvider.currentUser;
        if (currentUser != null) {
          final userData = currentUser.toJson();
          final event = isTyping ? 'user_typing' : 'user_stop_typing';
          socket.emit(event, {
            'userId': userData['id'],
            'groupId': groupId,
            'timestamp': DateTime.now().toIso8601String(),
          });
          debugPrint('💬 Sent typing event [$event] for user ${userData['id']} in group $groupId');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Could not get user from AuthProvider: $e');
      }
      debugPrint('⚠️ User ID not available for typing indicator');
      return;
    }

    final event = isTyping ? 'user_typing' : 'user_stop_typing';
    socket.emit(event, {
      'userId': userId,
      'groupId': groupId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('💬 Sent typing event [$event] for user $userId in group $groupId');
  }

  void markRead(int groupId, int messageId) {
    final socket = _sockets[groupId];
    if (socket != null && socket.connected) {
      // ✅ FIXED: Get user from AuthService
      final user = AuthService().currentUser;
      final userId = user?['id'];
      
      if (userId == null) {
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

  void debugConnectionStatus(int groupId) {
    final socket = _sockets[groupId];
    debugPrint('🔍 Socket.IO Debug for group $groupId:');
    debugPrint('   - Socket exists: ${socket != null}');
    debugPrint('   - Connected: ${socket?.connected ?? false}');
    debugPrint('   - ID: ${socket?.id}');
    debugPrint('   - Connection attempts: ${_connectionAttempts[groupId]}');
    debugPrint('   - WebSocket URL: ${Config.websocketUrl}');
    debugPrint('   - Live Chat Enabled: ${Config.enableLiveChat}');

    // ✅ FIXED: Get user from AuthService
    final user = AuthService().currentUser;
    if (user != null) {
      debugPrint('   - User ID: ${user['id']}');
      debugPrint('   - Username: ${user['username']}');
    } else {
      debugPrint('   - User ID: NOT FOUND - Authentication issue!');
      // ✅ Try AuthProvider as fallback
      try {
        final authProvider = AuthProvider();
        final currentUser = authProvider.currentUser;
        if (currentUser != null) {
          debugPrint('   - AuthProvider User ID: ${currentUser.id}');
          debugPrint('   - AuthProvider Username: ${currentUser.username}');
        }
      } catch (e) {
        debugPrint('   - AuthProvider error: $e');
      }
    }
  }

  List<dynamic> getCachedMembers(int groupId) {
    return _memberCache[groupId] ?? [];
  }

  int getMemberCount(int groupId) {
    return _memberCache[groupId]?.length ?? 0;
  }

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

  void disposeGroupMembers(int groupId) {
    _memberControllers[groupId]?.close();
    _memberControllers.remove(groupId);
    _memberCache.remove(groupId);
  }

  void disposeGroup(int groupId) {
    debugPrint('🔌 Disposing Socket.IO for group $groupId');

    final user = AuthService().currentUser;
    final userId = user?['id'];

    if (userId != null) {
      _sockets[groupId]?.emit('leave_group', {
        'groupId': groupId,
        'userId': userId,
      });
    }

    _cleanupGroupConnection(groupId);

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
    _messageCache.remove(groupId);
    _messageIds.remove(groupId);
    _messageContentHashes.remove(groupId);
  }

  void disposeAll() {
    debugPrint('🔌 Disposing all Socket.IO connections');

    for (final groupId in _sockets.keys.toList()) {
      disposeGroup(groupId);
    }

    _messageCache.clear();
    _messageIds.clear();
    _messageContentHashes.clear();
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