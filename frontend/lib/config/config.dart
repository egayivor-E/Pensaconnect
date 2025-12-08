import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class Config {
  // ================================
  // PRODUCTION DETECTION
  // ================================
  static bool get _isProduction {
    return kReleaseMode; // True for release builds, false for debug
  }

  // ================================
  // PRODUCTION DEFAULTS
  // ================================
  static const String _productionBackendUrl =
      'https://pensaconnect.onrender.com';
  static const String _productionWebsocketUrl =
      'wss://pensaconnect.onrender.com';
  static const String _productionYouTubeId = 'UCvVY7eg9Pw';

  // ================================
  // EXISTING CONFIGURATION - UPDATED
  // ================================

  static String get _rawBackendUrl {
    if (_isProduction) {
      debugPrint('🎯 PRODUCTION: Using backend: $_productionBackendUrl');
      return _productionBackendUrl;
    }

    // Development: Read from .env
    final backend = dotenv.env['BACKEND_URL'] ?? '';
    if (backend.isEmpty) {
      debugPrint(
        '⚠️ DEVELOPMENT: BACKEND_URL not in .env, using production fallback',
      );
      return _productionBackendUrl; // Fallback to production
    }

    final cleanedBackend = backend.endsWith('/')
        ? backend.substring(0, backend.length - 1)
        : backend;

    debugPrint('🔄 DEVELOPMENT: Using backend: $cleanedBackend');
    return cleanedBackend;
  }

  static String get apiBaseUrl {
    if (_isProduction) {
      return '$_productionBackendUrl/api/v1';
    }

    final prefix = dotenv.env['API_PREFIX'] ?? '';
    return '$_rawBackendUrl/$prefix';
  }

  static String get baseUrl => _rawBackendUrl;

  static String get anonymousMessagesUrl =>
      '$apiBaseUrl/anonymous/send-message';

  // ================================
  // IMPROVED LIVE STREAM CONFIGURATION
  // ================================

  // YouTube Configuration
  static String get youTubeVideoId {
    if (_isProduction) {
      debugPrint('🎯 PRODUCTION: Using YouTube ID: $_productionYouTubeId');
      return _productionYouTubeId; // Returns 'XsAks3LlbqA'
    }

    final videoId = dotenv.env['YOUTUBE_VIDEO_ID'] ?? 'UCvVY7eg9Pw';
    if (videoId.isEmpty || videoId == 'your_actual_youtube_id_here') {
      debugPrint('⚠️ YOUTUBE_VIDEO_ID is not set properly, using fallback');
      return 'UCvVY7eg9Pw'; // Just the video ID, not the full URL
    }

    // Clean up if someone accidentally pasted full URL
    final cleanedId = _extractYouTubeId(videoId);
    debugPrint('🎥 YouTube Video ID: $cleanedId');
    return cleanedId;
  }

  // Helper method to extract ID from various YouTube URL formats
  static String _extractYouTubeId(String input) {
    // If it's already just an ID (11 chars, no special characters)
    if (input.length == 11 && !input.contains('/') && !input.contains('?')) {
      return input;
    }

    // Try to extract from various URL formats
    try {
      final uri = Uri.parse(input);

      // Handle youtube.com/watch?v=VIDEO_ID
      if (uri.host.contains('youtube.com') &&
          uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v']!;
      }

      // Handle youtu.be/VIDEO_ID
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }

      // Handle youtube.com/embed/VIDEO_ID
      if (uri.host.contains('youtube.com') &&
          uri.pathSegments.contains('embed')) {
        final embedIndex = uri.pathSegments.indexOf('embed');
        if (embedIndex + 1 < uri.pathSegments.length) {
          return uri.pathSegments[embedIndex + 1];
        }
      }
    } catch (_) {
      // If parsing fails, return as-is (might already be an ID)
    }

    // Return original if we couldn't extract
    return input;
  }

  // ✅ FIXED: WebSocket Configuration for Flask-SocketIO
  static String get websocketUrl {
    if (_isProduction) {
      debugPrint('🎯 PRODUCTION: Using WebSocket: $_productionWebsocketUrl');
      return _productionWebsocketUrl;
    }

    // Development: Read from .env
    var wsUrl = dotenv.env['WEBSOCKET_URL'] ?? 'ws://127.0.0.1:5000';

    // Fix common WebSocket URL issues
    if (wsUrl.startsWith('http://')) {
      wsUrl = wsUrl.replaceFirst('http://', 'ws://');
    }
    if (wsUrl.startsWith('https://')) {
      wsUrl = wsUrl.replaceFirst('https://', 'wss://');
    }

    // ✅ CRITICAL FIX: Remove '/ws' suffix - Flask-SocketIO uses standard Socket.IO path
    if (wsUrl.endsWith('/ws')) {
      wsUrl = wsUrl.substring(0, wsUrl.length - 3);
    }

    debugPrint('🔌 DEVELOPMENT WebSocket URL: $wsUrl');
    return wsUrl;
  }

  // ✅ ADDED: Socket.IO specific configuration options
  static Map<String, dynamic> get socketIOOptions {
    return {
      'transports': ['websocket', 'polling'],
      'autoConnect': true,
      'forceNew': true,
      'timeout': 10000,
      'reconnection': true,
      'reconnectionAttempts': maxConnectionRetries,
      'reconnectionDelay': connectionRetryDelay * 1000,
      'reconnectionDelayMax': 5000,
    };
  }

  // ✅ ADDED: Socket.IO path configuration
  static String get socketIOPath {
    if (_isProduction) {
      return '/socket.io';
    }
    return dotenv.env['SOCKETIO_PATH'] ?? '/socket.io';
  }

  // Feature Flags with better debugging
  static bool get enableLiveChat {
    if (_isProduction) {
      debugPrint('🎯 PRODUCTION: Live chat ENABLED');
      return true;
    }

    final envValue = dotenv.env['ENABLE_LIVE_CHAT'];
    final isEnabled = envValue?.toLowerCase() == 'true' || envValue == '1';

    if (isEnabled) {
      debugPrint('✅ DEVELOPMENT: Live chat is ENABLED');
    } else {
      debugPrint(
        '❌ DEVELOPMENT: Live chat is DISABLED. ENABLE_LIVE_CHAT=$envValue',
      );
    }

    return isEnabled;
  }

  static bool get enableMessageModeration {
    if (_isProduction) {
      return true;
    }

    final envValue = dotenv.env['ENABLE_MESSAGE_MODERATION'];
    return envValue?.toLowerCase() == 'true' || envValue == '1';
  }

  // Rate Limiting Configuration
  static int get maxMessageLength {
    if (_isProduction) {
      return 1000;
    }
    return int.tryParse(dotenv.env['MAX_MESSAGE_LENGTH'] ?? '1000') ?? 1000;
  }

  static int get messageRateLimitSeconds {
    if (_isProduction) {
      return 2;
    }
    return int.tryParse(dotenv.env['MESSAGE_RATE_LIMIT_SECONDS'] ?? '2') ?? 2;
  }

  static Duration get messageRateLimit {
    return Duration(seconds: messageRateLimitSeconds);
  }

  static int get maxMessagesPerMinute {
    if (_isProduction) {
      return 30;
    }
    return int.tryParse(dotenv.env['MAX_MESSAGES_PER_MINUTE'] ?? '30') ?? 30;
  }

  // Live Stream Specific with type safety
  static String get liveStreamGroupId {
    if (_isProduction) {
      return '1';
    }

    final groupId = dotenv.env['LIVE_STREAM_GROUP_ID'] ?? '1';
    debugPrint('📺 Live Stream Group ID: $groupId');
    return groupId;
  }

  // Ensure we have an integer version for socket operations
  static int get liveStreamGroupIdInt {
    final groupId = liveStreamGroupId;
    final id = int.tryParse(groupId) ?? 1;
    debugPrint('🔢 Live Stream Group ID (int): $id');
    return id;
  }

  static int get messagePollingInterval {
    if (_isProduction) {
      return 5;
    }
    return int.tryParse(dotenv.env['MESSAGE_POLLING_INTERVAL'] ?? '5') ?? 5;
  }

  static int get maxConnectionRetries {
    if (_isProduction) {
      return 5;
    }
    return int.tryParse(dotenv.env['MAX_CONNECTION_RETRIES'] ?? '5') ?? 5;
  }

  static int get connectionRetryDelay {
    if (_isProduction) {
      return 3;
    }
    return int.tryParse(dotenv.env['CONNECTION_RETRY_DELAY'] ?? '3') ?? 3;
  }

  // New features from your .env
  static bool get enableTypingIndicators {
    if (_isProduction) {
      return true;
    }
    return dotenv.env['ENABLE_TYPING_INDICATORS']?.toLowerCase() == 'true';
  }

  static bool get enableReadReceipts {
    if (_isProduction) {
      return true;
    }
    return dotenv.env['ENABLE_READ_RECEIPTS']?.toLowerCase() == 'true';
  }

  static bool get enableMemberPresence {
    if (_isProduction) {
      return true;
    }
    return dotenv.env['ENABLE_MEMBER_PRESENCE']?.toLowerCase() == 'true';
  }

  // ================================
  // DEBUG METHODS - UPDATED
  // ================================

  static void printConfig() {
    debugPrint('\n🎯 CONFIGURATION SUMMARY:');
    debugPrint('  Mode: ${_isProduction ? "PRODUCTION" : "DEVELOPMENT"}');
    debugPrint('  Backend URL: $_rawBackendUrl');
    debugPrint('  API Base URL: $apiBaseUrl');
    debugPrint('  Live Chat Enabled: $enableLiveChat');
    debugPrint(
      '  Live Stream Group ID: $liveStreamGroupId (int: $liveStreamGroupIdInt)',
    );
    debugPrint('  YouTube Video ID: $youTubeVideoId');
    debugPrint('  WebSocket URL: $websocketUrl');
    debugPrint('  Max Message Length: $maxMessageLength');
    debugPrint('  Rate Limit: ${messageRateLimitSeconds}s');
    debugPrint('  Max Messages/Min: $maxMessagesPerMinute');
    debugPrint('  Polling Interval: ${messagePollingInterval}s');
    debugPrint('========================================\n');
  }

  // ✅ ADDED: Enhanced Socket.IO debugging
  static void printSocketConfig() {
    debugPrint('\n🔌 SOCKET.IO CONFIGURATION:');
    debugPrint('  Mode: ${_isProduction ? "PRODUCTION" : "DEVELOPMENT"}');
    debugPrint('  WebSocket URL: $websocketUrl');
    debugPrint('  Socket.IO Path: $socketIOPath');
    debugPrint('  Transports: websocket, polling');
    debugPrint('  Reconnection: true');
    debugPrint('  Max Retries: $maxConnectionRetries');
    debugPrint('  Retry Delay: ${connectionRetryDelay}s');
    debugPrint('  Live Stream Group ID: $liveStreamGroupIdInt');
    debugPrint('  Typing Indicators: $enableTypingIndicators');
    debugPrint('  Read Receipts: $enableReadReceipts');
    debugPrint('  Member Presence: $enableMemberPresence');
    debugPrint('========================================\n');
  }

  // ✅ ADDED: Connection validation method
  static void validateConfig() {
    try {
      // Test backend URL
      final backend = _rawBackendUrl;
      if (backend.isEmpty) {
        throw Exception('BACKEND_URL is not set');
      }

      // Test WebSocket URL
      final wsUrl = websocketUrl;
      if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
        throw Exception('WEBSOCKET_URL must start with ws:// or wss://');
      }

      debugPrint('✅ Configuration validation passed');
    } catch (e) {
      debugPrint('❌ Configuration validation failed: $e');
      rethrow;
    }
  }

  // ✅ ADDED: Debug mode info
  static void debugModeInfo() {
    debugPrint('\n🛠️  MODE DEBUG INFO:');
    debugPrint('  kReleaseMode: $kReleaseMode');
    debugPrint('  kDebugMode: $kDebugMode');
    debugPrint('  kProfileMode: $kProfileMode');
    debugPrint('  Is Production: $_isProduction');
    debugPrint('========================================\n');
  }
}
