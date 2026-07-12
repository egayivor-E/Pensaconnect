import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class Config {
  // ================================
  // EXISTING CONFIGURATION
  // ================================

  static String get _rawBackendUrl {
    final backend = dotenv.env['BACKEND_URL'] ?? '';
    if (backend.isEmpty) throw Exception('BACKEND_URL is not set in .env');
    return backend.endsWith('/')
        ? backend.substring(0, backend.length - 1)
        : backend;
  }

  static String get apiBaseUrl {
    final prefix = dotenv.env['API_PREFIX'] ?? 'api/v1'; // Default value
    final cleanPrefix = prefix.startsWith('/') ? prefix.substring(1) : prefix;
    return '$_rawBackendUrl/$cleanPrefix';
  }

  static String get baseUrl => _rawBackendUrl;

  static String get anonymousMessagesUrl =>
      '$apiBaseUrl/anonymous/send-message';

  // ================================
  // IMPROVED LIVE STREAM CONFIGURATION
  // ================================

  // YouTube Configuration
  static String get youTubeVideoId {
    final videoId = dotenv.env['YOUTUBE_VIDEO_ID'] ?? 'UCvVY7eg9Pw';
    if (videoId.isEmpty || videoId == 'your_actual_youtube_id_here') {
      debugPrint('⚠️ YOUTUBE_VIDEO_ID is not set properly');
      return 'UCvVY7eg9Pw'; // Fallback to a working video
    }
    debugPrint('🎥 YouTube Video ID: $videoId');
    return videoId;
  }

  static String get websocketUrl {
    // 1. Initial retrieval and immediate trim (removes \n and spaces)
    String url =
        (dotenv.env['WEBSOCKET_URL'] ??
                'https://pensaconnect-pjz9.onrender.com')
            .trim();

    // 2. Normalize scheme to HTTP/HTTPS for Socket.IO handshake
    if (url.startsWith('ws://')) {
      url = url.replaceFirst('ws://', 'http://');
    } else if (url.startsWith('wss://')) {
      url = url.replaceFirst('wss://', 'https://');
    }

    // 3. Remove path suffixes that interfere with socket.io
    if (url.endsWith('/ws')) {
      url = url.substring(0, url.length - 3);
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    // 4. Final debug to verify the handshake target
    debugPrint('🔌 Final Handshake URL: "$url"');
    return url.replaceFirst('wss://', 'https://');
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
    return dotenv.env['SOCKETIO_PATH'] ?? '/socket.io';
  }

  // Feature Flags with better debugging
  static bool get enableLiveChat {
    final envValue = dotenv.env['ENABLE_LIVE_CHAT'];
    final isEnabled = envValue?.toLowerCase() == 'true' || envValue == '1';

    if (isEnabled) {
      debugPrint('✅ Live chat is ENABLED');
    } else {
      debugPrint('❌ Live chat is DISABLED. ENABLE_LIVE_CHAT=$envValue');
    }

    return isEnabled;
  }

  static bool get enableMessageModeration {
    final envValue = dotenv.env['ENABLE_MESSAGE_MODERATION'];
    return envValue?.toLowerCase() == 'true' || envValue == '1';
  }

  // Rate Limiting Configuration
  static int get maxMessageLength {
    return int.tryParse(dotenv.env['MAX_MESSAGE_LENGTH'] ?? '1000') ?? 1000;
  }

  static int get messageRateLimitSeconds {
    return int.tryParse(dotenv.env['MESSAGE_RATE_LIMIT_SECONDS'] ?? '2') ?? 2;
  }

  static Duration get messageRateLimit {
    return Duration(seconds: messageRateLimitSeconds);
  }

  static int get maxMessagesPerMinute {
    return int.tryParse(dotenv.env['MAX_MESSAGES_PER_MINUTE'] ?? '30') ?? 30;
  }

  // Live Stream Specific with type safety
  static String get liveStreamGroupId {
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
    return int.tryParse(dotenv.env['MESSAGE_POLLING_INTERVAL'] ?? '5') ?? 5;
  }

  static int get maxConnectionRetries {
    return int.tryParse(dotenv.env['MAX_CONNECTION_RETRIES'] ?? '5') ?? 5;
  }

  static int get connectionRetryDelay {
    return int.tryParse(dotenv.env['CONNECTION_RETRY_DELAY'] ?? '3') ?? 3;
  }

  // New features from your .env
  static bool get enableTypingIndicators {
    return dotenv.env['ENABLE_TYPING_INDICATORS']?.toLowerCase() == 'true';
  }

  static bool get enableReadReceipts {
    return dotenv.env['ENABLE_READ_RECEIPTS']?.toLowerCase() == 'true';
  }

  static bool get enableMemberPresence {
    return dotenv.env['ENABLE_MEMBER_PRESENCE']?.toLowerCase() == 'true';
  }

  // ================================
  // DEBUG METHODS
  // ================================

  static void printConfig() {
    debugPrint('\n🎯 CONFIGURATION SUMMARY:');
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
}
