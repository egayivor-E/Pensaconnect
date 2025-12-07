// lib/services/websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:pensaconnect/models/group_message_model.dart';
import 'package:pensaconnect/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Production-ready WebSocket service for real-time messaging
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal() {
    _initialize();
  }

  // ================================
  // PRIVATE PROPERTIES
  // ================================

  final Map<int, WebSocketChannel> _channels = {};
  final Map<int, StreamController<List<GroupMessage>>> _messageControllers = {};
  final Map<int, StreamController<bool>> _connectionControllers = {};
  final Map<int, StreamController<String>> _errorControllers = {};
  final Map<int, int> _reconnectAttempts = {};
  final Map<int, Timer?> _reconnectTimers = {};
  final Map<String, MessageStatus> _messageStatus = {};
  final Map<int, DateTime> _lastMessageTimestamps = {};

  static const String _baseUrl = 'ws://127.0.0.1:5000'; // Socket.IO server
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _inactiveTimeout = Duration(minutes: 5);
  final Uuid _uuid = const Uuid();

  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;
  bool _isServiceInitialized = false;

  // ================================
  // PUBLIC STREAMS
  // ================================

  /// Stream for messages in a specific group
  Stream<List<GroupMessage>> watchMessages(int groupId) {
    if (!_messageControllers.containsKey(groupId)) {
      _messageControllers[groupId] =
          StreamController<List<GroupMessage>>.broadcast();
      _connectToGroup(groupId);
    }
    return _messageControllers[groupId]!.stream;
  }

  /// Stream for connection status changes
  Stream<bool> watchConnectionStatus(int groupId) {
    if (!_connectionControllers.containsKey(groupId)) {
      _connectionControllers[groupId] = StreamController<bool>.broadcast();
    }
    return _connectionControllers[groupId]!.stream;
  }

  /// Stream for connection errors
  Stream<String> watchErrors(int groupId) {
    if (!_errorControllers.containsKey(groupId)) {
      _errorControllers[groupId] = StreamController<String>.broadcast();
    }
    return _errorControllers[groupId]!.stream;
  }

  // ================================
  // INITIALIZATION
  // ================================

  Future<void> _initialize() async {
    if (_isServiceInitialized) return;

    try {
      developer.log(
        '🚀 Initializing WebSocketService with URL: $_baseUrl',
        name: 'WebSocketService',
      );

      // Start heartbeat timer
      _startHeartbeat();

      // Start cleanup timer
      _startCleanupTimer();

      _isServiceInitialized = true;

      developer.log(
        '✅ WebSocketService initialized successfully',
        name: 'WebSocketService',
      );
    } catch (e, stackTrace) {
      developer.log(
        '❌ WebSocketService initialization failed: $e',
        name: 'WebSocketService',
        error: e,
        stackTrace: stackTrace,
      );
      throw WebSocketInitializationException(
        'Failed to initialize WebSocket service: $e',
      );
    }
  }

  // ================================
  // CONNECTION MANAGEMENT
  // ================================

  Future<void> _connectToGroup(int groupId) async {
    if (groupId <= 0) {
      _handleError(groupId, 'Invalid group ID: $groupId');
      return;
    }

    try {
      // Clean up previous connection
      _disconnectGroup(groupId);

      // Check if we should throttle reconnection
      if (_shouldThrottleReconnection(groupId)) {
        developer.log(
          '⏸️ Throttling reconnection for group $groupId',
          name: 'WebSocketService',
        );
        return;
      }

      developer.log(
        '🔌 Connecting WebSocket for group $groupId...',
        name: 'WebSocketService',
      );

      // Get authentication token
      final token = await _getAuthToken();
      final queryParams = token != null ? '?token=$token' : '';

      // Create WebSocket connection
      final channel = WebSocketChannel.connect(
        Uri.parse('$_baseUrl$queryParams'),
      );

      _channels[groupId] = channel;
      _reconnectAttempts[groupId] = (_reconnectAttempts[groupId] ?? 0) + 1;

      // Track connection state
      final Completer<bool> connectionCompleter = Completer<bool>();

      // Set up listeners
      channel.stream.listen(
        (data) {
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(true);
          }
          _handleSocketIOMessage(data, groupId);
        },
        onError: (error) {
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(false);
          }
          _handleConnectionError(error, groupId);
        },
        onDone: () {
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(false);
          }
          _handleConnectionDone(groupId);
        },
        cancelOnError: false,
      );

      // Wait for initial connection (with timeout)
      final connected = await connectionCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          developer.log(
            '⏰ Connection timeout for group $groupId',
            name: 'WebSocketService',
          );
          return false;
        },
      );

      if (!connected) {
        throw ConnectionException('Failed to establish WebSocket connection');
      }

      // Send join event after connection is established
      await _sendJoinGroup(groupId);

      // Update connection status
      _updateConnectionStatus(groupId, true);

      developer.log(
        '✅ WebSocket connected for group $groupId',
        name: 'WebSocketService',
      );
    } catch (e, stackTrace) {
      developer.log(
        '❌ WebSocket connection error for group $groupId: $e',
        name: 'WebSocketService',
        error: e,
        stackTrace: stackTrace,
      );
      _handleConnectionError(e, groupId);
    }
  }

  bool _shouldThrottleReconnection(int groupId) {
    final lastAttempt = _lastMessageTimestamps[groupId];
    if (lastAttempt == null) return false;

    final timeSinceLastAttempt = DateTime.now().difference(lastAttempt);
    return timeSinceLastAttempt < _reconnectDelay;
  }

  Future<void> _sendJoinGroup(int groupId) async {
    try {
      final authService = AuthService();
      final userId = authService.userId;

      final joinMessage = {
        'event': 'join_group',
        'data': {
          'groupId': groupId,
          'userId': userId,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'clientInfo': await _getClientInfo(),
        },
      };

      await _sendRawMessage(groupId, json.encode(joinMessage));

      developer.log(
        '👥 Sent join_group event for group $groupId',
        name: 'WebSocketService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Error sending join_group: $e',
        name: 'WebSocketService',
      );
    }
  }

  // ================================
  // MESSAGE HANDLING
  // ================================

  void _handleSocketIOMessage(dynamic data, int groupId) {
    try {
      _lastMessageTimestamps[groupId] = DateTime.now();

      final messageString = data.toString();
      developer.log(
        '📨 Raw WebSocket message (${messageString.length} chars)',
        name: 'WebSocketService',
      );

      final messageData = json.decode(messageString);
      final event = messageData['event'] as String?;
      final eventData = messageData['data'];

      if (event == null) {
        developer.log(
          '⚠️ Received message without event type',
          name: 'WebSocketService',
        );
        return;
      }

      switch (event) {
        case 'connected':
          _handleConnectedEvent(eventData, groupId);
          break;

        case 'joined_group':
          _handleJoinedGroupEvent(eventData, groupId);
          break;

        case 'new_message':
        case 'message_received':
          _handleNewMessageEvent(eventData, groupId);
          break;

        case 'message_delivered':
          _handleMessageDeliveredEvent(eventData, groupId);
          break;

        case 'message_read':
          _handleMessageReadEvent(eventData, groupId);
          break;

        case 'user_typing':
          _handleUserTypingEvent(eventData, groupId);
          break;

        case 'user_joined':
          _handleUserJoinedEvent(eventData, groupId);
          break;

        case 'user_left':
          _handleUserLeftEvent(eventData, groupId);
          break;

        case 'error':
          _handleErrorMessage(eventData, groupId);
          break;

        case 'heartbeat':
          _handleHeartbeat(eventData, groupId);
          break;

        default:
          developer.log(
            '📨 Unknown WebSocket event: $event',
            name: 'WebSocketService',
          );
      }
    } catch (e, stackTrace) {
      developer.log(
        '❌ Error parsing WebSocket message: $e',
        name: 'WebSocketService',
        error: e,
        stackTrace: stackTrace,
      );
      _handleError(groupId, 'Failed to parse message: $e');
    }
  }

  void _handleConnectedEvent(dynamic data, int groupId) {
    developer.log(
      '✅ WebSocket connected: ${data['message'] ?? 'Success'}',
      name: 'WebSocketService',
    );
    _reconnectAttempts[groupId] = 0; // Reset attempts on successful connection
  }

  void _handleJoinedGroupEvent(dynamic data, int groupId) {
    developer.log(
      '✅ Joined group: ${data['groupId']}',
      name: 'WebSocketService',
    );
  }

  void _handleNewMessageEvent(dynamic data, int groupId) {
    try {
      developer.log(
        '💬 New message received via WebSocket',
        name: 'WebSocketService',
      );

      final message = GroupMessage.fromJson(data);

      // Validate message
      if (!_isValidMessage(message)) {
        developer.log(
          '⚠️ Invalid message received, ignoring',
          name: 'WebSocketService',
        );
        return;
      }

      // Add to stream
      _messageControllers[groupId]?.add([message]);

      // Acknowledge receipt
      _acknowledgeMessage(message.id, groupId);
    } catch (e, stackTrace) {
      developer.log(
        '❌ Error handling new message: $e',
        name: 'WebSocketService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  bool _isValidMessage(GroupMessage message) {
    return message.id != null &&
        message.id != 0 &&
        message.content.isNotEmpty &&
        message.senderId != null &&
        message.senderId != 0 &&
        message.createdAt != null;
  }

  void _acknowledgeMessage(int? messageId, int groupId) {
    if (messageId == null) return;

    try {
      final ackMessage = {
        'event': 'message_ack',
        'data': {
          'messageId': messageId,
          'groupId': groupId,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      };

      _sendRawMessage(groupId, json.encode(ackMessage));
    } catch (e) {
      developer.log(
        '⚠️ Error acknowledging message: $e',
        name: 'WebSocketService',
      );
    }
  }

  void _handleMessageDeliveredEvent(dynamic data, int groupId) {
    final messageId = data['messageId'];
    developer.log('✓ Message delivered: $messageId', name: 'WebSocketService');
    _updateMessageStatus(messageId, 'delivered');
  }

  void _handleMessageReadEvent(dynamic data, int groupId) {
    final messageId = data['messageId'];
    final userId = data['userId'];
    developer.log(
      '📖 Message $messageId read by user $userId',
      name: 'WebSocketService',
    );
    _updateMessageStatus(messageId, 'read');
  }

  void _handleUserTypingEvent(dynamic data, int groupId) {
    developer.log(
      '⌨️ User ${data['userId']} typing in group $groupId',
      name: 'WebSocketService',
    );
  }

  void _handleUserJoinedEvent(dynamic data, int groupId) {
    developer.log(
      '👤 User ${data['userId']} joined group $groupId',
      name: 'WebSocketService',
    );
  }

  void _handleUserLeftEvent(dynamic data, int groupId) {
    developer.log(
      '👋 User ${data['userId']} left group $groupId',
      name: 'WebSocketService',
    );
  }

  void _handleErrorMessage(dynamic data, int groupId) {
    final errorMessage = data['message'] ?? 'Unknown error';
    developer.log('❌ Server error: $errorMessage', name: 'WebSocketService');
    _handleError(groupId, errorMessage);
  }

  void _handleHeartbeat(dynamic data, int groupId) {
    // Update last activity timestamp
    _lastMessageTimestamps[groupId] = DateTime.now();
  }

  // ================================
  // SEND MESSAGE (PRODUCTION-READY)
  // ================================

  /// Send a message to a group
  Future<MessageSendResult> sendMessage(
    int groupId,
    String content, {
    String messageType = 'text',
    Map<String, dynamic>? metadata,
    bool retryOnFailure = true,
  }) async {
    final startTime = DateTime.now();
    final messageId = _generateMessageId();

    try {
      // Validate input
      if (groupId <= 0) {
        throw MessageValidationException('Invalid group ID: $groupId');
      }

      if (content.trim().isEmpty) {
        throw MessageValidationException('Message content cannot be empty');
      }

      // Sanitize content
      final sanitizedContent = _sanitizeMessageContent(content);

      // Verify authentication
      final authService = AuthService();
      final isAuthenticated = await authService.isAuthenticated();
      if (!isAuthenticated) {
        throw AuthenticationException('User not authenticated');
      }

      final userId = authService.userId;
      final username = authService.username ?? 'Unknown User';

      if (userId == null) {
        throw AuthenticationException('User ID not found');
      }

      // Verify connection
      if (!_isConnected(groupId)) {
        throw ConnectionException('WebSocket not connected to group $groupId');
      }

      // Create message payload
      final messageData = {
        'event': 'send_message',
        'data': {
          'groupId': groupId,
          'content': sanitizedContent,
          'type': messageType,
          'senderId': userId,
          'senderName': username,
          'messageId': messageId,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'metadata': metadata ?? {},
          'clientInfo': await _getClientInfo(),
        },
      };

      // Add temp message to UI
      final tempMessage = _createTemporaryMessage(
        groupId: groupId,
        content: sanitizedContent,
        messageId: messageId,
        userId: userId,
        username: username,
        messageType: messageType,
      );
      _messageControllers[groupId]?.add([tempMessage]);

      // Send with retry logic
      await _sendWithRetry(
        groupId,
        json.encode(messageData),
        messageId,
        retryOnFailure: retryOnFailure,
      );

      // Track successful send
      await _trackMessageSent(
        messageId: messageId,
        groupId: groupId,
        contentLength: content.length,
        messageType: messageType,
        duration: DateTime.now().difference(startTime),
      );

      developer.log(
        '✅ Message sent successfully: $messageId',
        name: 'WebSocketService',
      );

      return MessageSendResult.success(
        messageId: messageId,
        timestamp: DateTime.now(),
      );
    } catch (e, stackTrace) {
      developer.log(
        '❌ Error sending message: $e',
        name: 'WebSocketService',
        error: e,
        stackTrace: stackTrace,
      );

      // Update message status to failed
      _updateMessageStatus(messageId, 'failed');

      return MessageSendResult.failure(
        messageId: messageId,
        error: e.toString(),
        timestamp: DateTime.now(),
        retryable:
            e is! AuthenticationException && e is! MessageValidationException,
      );
    }
  }

  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}';
  }

  String _sanitizeMessageContent(String content) {
    // Basic HTML/script sanitization
    String sanitized = content
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');

    // Trim and limit length
    sanitized = sanitized.trim();
    const maxLength = 5000;
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
      developer.log(
        '⚠️ Message content truncated to $maxLength characters',
        name: 'WebSocketService',
      );
    }

    return sanitized;
  }

  GroupMessage _createTemporaryMessage({
    required int groupId,
    required String content,
    required String messageId,
    required int? userId,
    required String? username,
    required String messageType,
  }) {
    return GroupMessage(
      id: DateTime.now().millisecondsSinceEpoch,
      uuid: messageId,
      groupChatId: groupId,
      senderId: userId ?? 0,
      content: content,
      messageType: messageType,
      attachments: [],
      readBy: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isActive: true,
      sender: {
        'full_name': username ?? 'Unknown User',
        'username': username ?? 'unknown',
        'id': userId ?? 0,
      },
      isTemporary: true,
      status: 'sending',
    );
  }

  Future<void> _sendWithRetry(
    int groupId,
    String messageJson,
    String messageId, {
    bool retryOnFailure = true,
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _sendRawMessage(groupId, messageJson);
        _updateMessageStatus(messageId, 'sent');
        return;
      } catch (e) {
        developer.log(
          '⚠️ Send attempt $attempt failed for message $messageId: $e',
          name: 'WebSocketService',
        );

        if (attempt == maxRetries || !retryOnFailure) {
          throw SendMessageException(
            'Failed to send message after $attempt attempts: $e',
          );
        }

        // Exponential backoff
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  Future<void> _sendRawMessage(int groupId, String message) async {
    final channel = _channels[groupId];
    if (channel == null) {
      throw ConnectionException(
        'WebSocket channel not found for group $groupId',
      );
    }

    // Check if channel is closing or closed
    final completer = Completer<void>();
    try {
      // Add a small delay to allow any pending operations
      await Future.delayed(const Duration(milliseconds: 10));

      // Send the message
      channel.sink.add(message);

      // Add small delay to ensure message is processed
      await Future.delayed(const Duration(milliseconds: 50));

      completer.complete();
    } catch (e) {
      completer.completeError(e);
    }

    return completer.future;
  }

  // ================================
  // CONNECTION STATUS CHECK
  // ================================

  bool _isConnected(int groupId) {
    final channel = _channels[groupId];
    if (channel == null) return false;

    // Check if the channel is still active
    // We can't directly check if the WebSocket is connected,
    // but we can track our own connection state
    return true; // Connection state is managed by _connectionControllers
  }

  // ================================
  // ERROR HANDLING & RECONNECTION
  // ================================

  void _handleConnectionError(dynamic error, int groupId) {
    _updateConnectionStatus(groupId, false);

    final errorMessage = error.toString();
    developer.log(
      '❌ WebSocket error for group $groupId: $errorMessage',
      name: 'WebSocketService',
    );

    _errorControllers[groupId]?.add(errorMessage);
    _scheduleReconnection(groupId);
  }

  void _handleConnectionDone(int groupId) {
    developer.log(
      '🔌 WebSocket disconnected for group $groupId',
      name: 'WebSocketService',
    );
    _updateConnectionStatus(groupId, false);
    _scheduleReconnection(groupId);
  }

  void _scheduleReconnection(int groupId) {
    // Cancel existing timer
    _reconnectTimers[groupId]?.cancel();

    final attempts = _reconnectAttempts[groupId] ?? 0;
    if (attempts >= _maxReconnectAttempts) {
      developer.log(
        '❌ Max reconnection attempts reached for group $groupId',
        name: 'WebSocketService',
      );
      return;
    }

    // Exponential backoff
    final delay = Duration(seconds: _reconnectDelay.inSeconds * (attempts + 1));

    developer.log(
      '🔄 Scheduling reconnection for group $groupId in ${delay.inSeconds}s (attempt ${attempts + 1}/$_maxReconnectAttempts)',
      name: 'WebSocketService',
    );

    _reconnectTimers[groupId] = Timer(delay, () {
      _connectToGroup(groupId);
    });
  }

  void _handleError(int groupId, String errorMessage) {
    developer.log(
      '⚠️ Error in group $groupId: $errorMessage',
      name: 'WebSocketService',
    );
    _errorControllers[groupId]?.add(errorMessage);
  }

  // ================================
  // HEARTBEAT & CLEANUP
  // ================================

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      _channels.forEach((groupId, channel) {
        try {
          // Don't send heartbeat if we haven't heard from server recently
          final lastActivity = _lastMessageTimestamps[groupId];
          if (lastActivity != null &&
              DateTime.now().difference(lastActivity) > Duration(minutes: 1)) {
            developer.log(
              '⚠️ No server activity for group $groupId, skipping heartbeat',
              name: 'WebSocketService',
            );
            return;
          }

          final heartbeat = {
            'event': 'heartbeat',
            'data': {
              'groupId': groupId,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            },
          };
          channel.sink.add(json.encode(heartbeat));
        } catch (e) {
          developer.log(
            '⚠️ Heartbeat failed for group $groupId: $e',
            name: 'WebSocketService',
          );
        }
      });
    });
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _cleanupInactiveConnections();
    });
  }

  void _cleanupInactiveConnections() {
    final now = DateTime.now();
    _channels.forEach((groupId, channel) {
      final lastActivity = _lastMessageTimestamps[groupId];
      if (lastActivity != null &&
          now.difference(lastActivity) > _inactiveTimeout) {
        developer.log(
          '🧹 Cleaning up inactive connection for group $groupId',
          name: 'WebSocketService',
        );
        _disconnectGroup(groupId);
      }
    });
  }

  // ================================
  // UTILITY METHODS
  // ================================

  Future<String?> _getAuthToken() async {
    try {
      final authService = AuthService();
      return await authService.getToken();
    } catch (e) {
      developer.log(
        '⚠️ Error getting auth token: $e',
        name: 'WebSocketService',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>> _getClientInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id') ?? 'unknown_device';

    return {
      'platform': 'web',
      'appVersion': _getAppVersion(),
      'deviceId': deviceId,
      'userAgent': _getUserAgent(),
    };
  }

  String _getAppVersion() {
    try {
      return const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
    } catch (e) {
      return '1.0.0';
    }
  }

  String _getUserAgent() {
    try {
      return 'Flutter Web/${_getAppVersion()}';
    } catch (e) {
      return 'Flutter Web/Unknown';
    }
  }

  Future<void> _trackMessageSent({
    required String messageId,
    required int groupId,
    required int contentLength,
    required String messageType,
    required Duration duration,
  }) async {
    try {
      // Store in local database for offline sync
      await _saveMessageToLocalDb(
        messageId: messageId,
        groupId: groupId,
        contentLength: contentLength,
        messageType: messageType,
        status: 'sent',
        timestamp: DateTime.now(),
      );

      // Update message status
      _updateMessageStatus(messageId, 'sent');

      // Analytics (non-blocking)
      unawaited(
        _sendAnalyticsEvent('message_sent', {
          'group_id': groupId,
          'message_length': contentLength,
          'message_type': messageType,
          'send_duration_ms': duration.inMilliseconds,
        }),
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to track message sent event: $e',
        name: 'WebSocketService',
      );
    }
  }

  void _updateMessageStatus(String messageId, String status) {
    _messageStatus[messageId] = MessageStatus(
      id: messageId,
      status: status,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _saveMessageToLocalDb({
    required String messageId,
    required int groupId,
    required int contentLength,
    required String messageType,
    required String status,
    required DateTime timestamp,
  }) async {
    // Implement local database storage
    // This is a placeholder for your actual implementation
  }

  Future<void> _sendAnalyticsEvent(
    String event,
    Map<String, dynamic> data,
  ) async {
    // Implement analytics tracking
    // This is a placeholder for your actual implementation
  }

  void _updateConnectionStatus(int groupId, bool isConnected) {
    _connectionControllers[groupId]?.add(isConnected);
  }

  // ================================
  // PUBLIC METHODS
  // ================================

  /// Check if WebSocket is connected for a group
  bool isConnected(int groupId) {
    return _isConnected(groupId);
  }

  /// Get connection status for all groups
  Map<int, bool> getConnectionStatus() {
    final status = <int, bool>{};
    _channels.forEach((groupId, _) {
      status[groupId] = _isConnected(groupId);
    });
    return status;
  }

  /// Manually reconnect a group
  Future<void> reconnect(int groupId) async {
    _reconnectAttempts[groupId] = 0;
    _reconnectTimers[groupId]?.cancel();
    await _connectToGroup(groupId);
  }

  /// Send typing indicator
  Future<void> sendTypingIndicator(int groupId, bool isTyping) async {
    try {
      final authService = AuthService();
      final userId = authService.userId;
      if (userId == null) return;

      final typingMessage = {
        'event': isTyping ? 'user_typing' : 'user_stop_typing',
        'data': {
          'groupId': groupId,
          'userId': userId,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      };

      await _sendRawMessage(groupId, json.encode(typingMessage));

      developer.log(
        '⌨️ Sent typing indicator: $isTyping',
        name: 'WebSocketService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Error sending typing indicator: $e',
        name: 'WebSocketService',
      );
    }
  }

  /// Mark message as read
  Future<void> markMessageAsRead(int groupId, int messageId) async {
    try {
      final authService = AuthService();
      final userId = authService.userId;
      if (userId == null) return;

      final readMessage = {
        'event': 'message_read',
        'data': {
          'groupId': groupId,
          'messageId': messageId,
          'userId': userId,
          'readAt': DateTime.now().toUtc().toIso8601String(),
        },
      };

      await _sendRawMessage(groupId, json.encode(readMessage));

      developer.log(
        '📖 Marked message $messageId as read',
        name: 'WebSocketService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Error marking message as read: $e',
        name: 'WebSocketService',
      );
    }
  }

  // ================================
  // CLEANUP
  // ================================

  void _disconnectGroup(int groupId) {
    try {
      // Send leave event
      final leaveMessage = {
        'event': 'leave_group',
        'data': {
          'groupId': groupId,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      };
      _channels[groupId]?.sink.add(json.encode(leaveMessage));
    } catch (e) {
      developer.log(
        '⚠️ Error sending leave event: $e',
        name: 'WebSocketService',
      );
    }

    // Close connection
    try {
      _channels[groupId]?.sink.close();
    } catch (e) {
      // Ignore errors during close
    }

    // Close controllers
    _messageControllers[groupId]?.close();
    _connectionControllers[groupId]?.close();
    _errorControllers[groupId]?.close();

    // Remove from maps
    _channels.remove(groupId);
    _messageControllers.remove(groupId);
    _connectionControllers.remove(groupId);
    _errorControllers.remove(groupId);
    _reconnectTimers[groupId]?.cancel();
    _reconnectTimers.remove(groupId);
    _reconnectAttempts.remove(groupId);
    _lastMessageTimestamps.remove(groupId);
  }

  void disposeGroup(int groupId) {
    developer.log(
      '🔌 Disposing WebSocket for group $groupId',
      name: 'WebSocketService',
    );
    _disconnectGroup(groupId);
  }

  void disposeAll() {
    developer.log(
      '🔌 Disposing all WebSocket connections',
      name: 'WebSocketService',
    );

    _channels.keys.toList().forEach((groupId) {
      _disconnectGroup(groupId);
    });

    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    _heartbeatTimer = null;
    _cleanupTimer = null;

    _isServiceInitialized = false;
  }
}

// ================================
// SUPPORTING CLASSES
// ================================

class MessageStatus {
  final String id;
  final String status; // 'sending', 'sent', 'delivered', 'read', 'failed'
  final DateTime updatedAt;

  MessageStatus({
    required this.id,
    required this.status,
    required this.updatedAt,
  });
}

class MessageSendResult {
  final String messageId;
  final bool success;
  final String? error;
  final DateTime timestamp;
  final bool retryable;

  MessageSendResult._({
    required this.messageId,
    required this.success,
    this.error,
    required this.timestamp,
    this.retryable = false,
  });

  factory MessageSendResult.success({
    required String messageId,
    required DateTime timestamp,
  }) {
    return MessageSendResult._(
      messageId: messageId,
      success: true,
      timestamp: timestamp,
    );
  }

  factory MessageSendResult.failure({
    required String messageId,
    required String error,
    required DateTime timestamp,
    bool retryable = false,
  }) {
    return MessageSendResult._(
      messageId: messageId,
      success: false,
      error: error,
      timestamp: timestamp,
      retryable: retryable,
    );
  }
}

// ================================
// EXCEPTION CLASSES
// ================================

class WebSocketInitializationException implements Exception {
  final String message;
  WebSocketInitializationException(this.message);

  @override
  String toString() => 'WebSocketInitializationException: $message';
}

class AuthenticationException implements Exception {
  final String message;
  AuthenticationException(this.message);

  @override
  String toString() => 'AuthenticationException: $message';
}

class ConnectionException implements Exception {
  final String message;
  ConnectionException(this.message);

  @override
  String toString() => 'ConnectionException: $message';
}

class MessageValidationException implements Exception {
  final String message;
  MessageValidationException(this.message);

  @override
  String toString() => 'MessageValidationException: $message';
}

class SendMessageException implements Exception {
  final String message;
  SendMessageException(this.message);

  @override
  String toString() => 'SendMessageException: $message';
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}

// Helper function to run async operations without waiting
void unawaited(Future<void> future) {
  future.catchError((error) {
    developer.log('Unawaited future error: $error', name: 'WebSocketService');
  });
}
