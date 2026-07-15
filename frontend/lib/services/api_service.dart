import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 🔹 API Service Class - Production Ready
class ApiService {
  static const Duration timeoutDuration = Duration(seconds: 30);
  static String? _authToken;
  static String? _refreshToken;
  static Timer? _refreshTimer;

  static final _secureStorage = const FlutterSecureStorage();
  static List<RequestInterceptor> requestInterceptors = [];
  static List<ResponseInterceptor> responseInterceptors = [];

  // === INITIALIZATION CONTROL ===
  static bool _isInitialized = false;
  static Completer<void>? _initCompleter;

  // === TOKEN STREAM ===
  static final StreamController<String?> _tokenStreamController =
      StreamController<String?>.broadcast();
  static Stream<String?> get tokenStream => _tokenStreamController.stream;
  static String? get authToken => _authToken;

  /// Get the current access token (async version for compatibility)
  static Future<String?> getToken() async {
    await ensureInitialized(); // Ensure we're initialized
    return _authToken;
  }

  // === INITIALIZATION ===
  static Future<void> init() async {
    // Prevent multiple initializations
    if (_isInitialized) return;

    // If initialization is in progress, wait for it
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      developer.log("🔄 Initializing ApiService...", name: "ApiService");

      _authToken = await _secureStorage.read(key: 'access_token');
      _refreshToken = await _secureStorage.read(key: 'refresh_token');

      developer.log(
        "🪙 Loaded access token: ${_authToken != null}",
        name: "ApiService",
      );
      developer.log(
        "🪙 Loaded refresh token: ${_refreshToken != null}",
        name: "ApiService",
      );

      _tokenStreamController.add(_authToken);

      if (_authToken != null && _refreshToken != null) {
        _scheduleTokenRefresh();
      }

      _isInitialized = true;
      _initCompleter!.complete();

      developer.log(
        "✅ ApiService initialized successfully",
        name: "ApiService",
      );
    } catch (e) {
      developer.log("❌ ApiService init failed: $e", name: "ApiService");
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  // === ENSURE INITIALIZATION BEFORE ANY API CALL ===
  static Future<void> ensureInitialized() async {
    if (!_isInitialized) {
      if (_initCompleter != null) {
        // Initialization in progress - wait for it
        return _initCompleter!.future;
      } else {
        // Start initialization
        return init();
      }
    }
  }

  // === SET TOKENS ===
  static Future<void> setTokens(
    String? accessToken,
    String? refreshToken,
  ) async {
    await ensureInitialized(); // Ensure we're initialized before modifying tokens

    _authToken = accessToken;
    _refreshToken = refreshToken;

    if (accessToken != null) {
      await _secureStorage.write(key: 'access_token', value: accessToken);
      if (kDebugMode) {
        developer.log("🔑 Access token saved", name: "ApiService");
      }
    } else {
      await _secureStorage.delete(key: 'access_token');
    }

    if (refreshToken != null) {
      await _secureStorage.write(key: 'refresh_token', value: refreshToken);
      if (kDebugMode) {
        developer.log("🔄 Refresh token saved", name: "ApiService");
      }
    } else {
      await _secureStorage.delete(key: 'refresh_token');
    }

    _tokenStreamController.add(_authToken);
    _scheduleTokenRefresh();
  }

  static Future<void> clearTokens() async {
    await ensureInitialized(); // Ensure we're initialized before clearing tokens

    _authToken = null;
    _refreshToken = null;
    _refreshTimer?.cancel();

    await _secureStorage.delete(key: 'access_token');
    await _secureStorage.delete(key: 'refresh_token');

    if (kDebugMode) {
      developer.log("🚪 Tokens cleared (logout)", name: "ApiService");
    }
    _tokenStreamController.add(null);
  }

  // === AUTO REFRESH ===
  static void _scheduleTokenRefresh() {
    _refreshTimer?.cancel();
    const refreshBefore = Duration(minutes: 14);
    _refreshTimer = Timer(refreshBefore, () async => await refreshToken());
  }

  static Future<void> refreshToken({int retry = 0}) async {
    await ensureInitialized(); // Ensure we're initialized before token refresh

    if (_refreshToken == null) {
      if (kDebugMode) {
        developer.log("⚠️ No refresh token available", name: "ApiService");
      }
      return;
    }

    try {
      final uri = _buildUri('auth/refresh');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $_refreshToken',
            },
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newAccess = data['data']?['access_token'];
        final newRefresh = data['data']?['refresh_token'] ?? _refreshToken;

        if (newAccess != null) {
          await setTokens(newAccess, newRefresh);
          if (kDebugMode) {
            developer.log("✅ Token refreshed successfully", name: "ApiService");
          }
          return;
        }
      }

      if (retry < 2) {
        await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        return refreshToken(retry: retry + 1);
      }

      await clearTokens();
    } catch (e) {
      if (kDebugMode) developer.log("❌ Refresh error: $e", name: "ApiService");
      if (retry < 2) {
        await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        return refreshToken(retry: retry + 1);
      }
      await clearTokens();
    }
  }

  static Future<void> _ensureValidToken() async {
    await ensureInitialized(); // Ensure we're initialized before token validation

    if (_authToken != null && _isTokenExpired(_authToken!)) {
      if (kDebugMode) {
        developer.log(
          "🔄 Access token expired → refreshing...",
          name: "ApiService",
        );
      }
      await refreshToken();
    }
  }

  static bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final payloadMap = json.decode(payload);
      final exp = payloadMap['exp'];
      if (exp == null) return true;

      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expiryDate.subtract(Duration(seconds: 30)));
    } catch (_) {
      return true;
    }
  }

  // Add this to your ApiService class
  static Future<void> debugTokenStatus() async {
    developer.log("🔍 === DEBUG TOKEN STATUS ===", name: "ApiService");

    // Check what's in secure storage
    final storedAccessToken = await _secureStorage.read(key: 'access_token');
    final storedRefreshToken = await _secureStorage.read(key: 'refresh_token');

    developer.log(
      "🔍 Stored Access Token: $storedAccessToken",
      name: "ApiService",
    );
    developer.log(
      "🔍 Stored Refresh Token: $storedRefreshToken",
      name: "ApiService",
    );
    developer.log("🔍 Memory Access Token: $_authToken", name: "ApiService");
    developer.log(
      "🔍 Memory Refresh Token: $_refreshToken",
      name: "ApiService",
    );
    developer.log("🔍 Is Initialized: $_isInitialized", name: "ApiService");
    developer.log("🔍 ===========================", name: "ApiService");
  }

  // Add this to ApiService for debugging
  static Future<void> debugSecureStorage() async {
    developer.log("🔍 === DEBUG SECURE STORAGE ===");
    try {
      final access = await _secureStorage.read(key: 'access_token');
      final refresh = await _secureStorage.read(key: 'refresh_token');
      developer.log("🔍 Secure Storage - Access Token: $access");
      developer.log("🔍 Secure Storage - Refresh Token: $refresh");
      developer.log("🔍 ============================");
    } catch (e) {
      developer.log("❌ Secure Storage Error: $e");
    }
  }

  // --- CONFIG ---
  static String get baseUrl {
    try {
      String backend = dotenv.get('BACKEND_URL');
      // ✅ FIX: Strip trailing slash if present
      if (backend.endsWith('/')) {
        backend = backend.substring(0, backend.length - 1);
      }
      return backend; // Returns clean string, e.g., "http://127.0.0.1:5000"
    } catch (_) {
      const fallback = 'https://pensaconnect.onrender.com';
      // ... (logging remains the same)
      return fallback;
    }
  }

  static String get _apiPrefix {
    try {
      String prefix = dotenv.get('API_PREFIX');

      // ✅ FIX 1: Strip leading slash
      if (prefix.startsWith('/')) {
        prefix = prefix.substring(1);
      }
      // ✅ FIX 2: Strip trailing slash
      if (prefix.endsWith('/')) {
        prefix = prefix.substring(0, prefix.length - 1);
      }

      // Returns clean string, e.g., "api/v1"
      return prefix.isNotEmpty ? prefix : 'api/v1';
    } catch (_) {
      // Fallback should also be clean
      return 'api/v1';
    }
  }

  // === REQUEST HELPERS ===
  static Future<http.Response> get(
    String endpoint, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    await ensureInitialized(); // ← CRITICAL: Wait for init
    await _ensureValidToken();
    final uri = _buildUri(endpoint, queryParams: queryParams);

    final request = http.Request('GET', uri);
    request.headers.addAll(await authHeaders());
    if (headers != null) request.headers.addAll(headers);
    _runRequestInterceptors(request);

    final response = await http.Response.fromStream(
      await request.send().timeout(timeoutDuration),
    );
    _runResponseInterceptors(response);
    return _handleResponse(response);
  }

  static Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    await ensureInitialized(); // ← CRITICAL: Wait for init

    developer.log("🚀 STARTING POST REQUEST", name: "ApiService");
    developer.log("📝 Endpoint: $endpoint", name: "ApiService");

    await _ensureValidToken();
    final uri = _buildUri(endpoint);
    developer.log("🔗 Built URI: $uri", name: "ApiService");

    final request = http.Request('POST', uri);
    developer.log("📋 Creating POST request...", name: "ApiService");

    // Get auth headers FIRST
    final defaultHeaders = await authHeaders();
    developer.log("📤 Default Headers: $defaultHeaders", name: "ApiService");
    request.headers.addAll(defaultHeaders);

    // Then add custom headers, but ensure Content-Type is preserved
    if (headers != null) {
      developer.log("📤 Custom Headers: $headers", name: "ApiService");
      request.headers.addAll(headers);
    }

    // Ensure Content-Type is set for JSON
    request.headers['Content-Type'] = 'application/json';
    developer.log("📤 Final Headers: ${request.headers}", name: "ApiService");

    request.body = json.encode(body);
    developer.log("📦 Request Body: ${request.body}", name: "ApiService");

    developer.log("🔄 Running request interceptors...", name: "ApiService");
    _runRequestInterceptors(request);

    developer.log(
      "⏳ Sending request with timeout: $timeoutDuration",
      name: "ApiService",
    );
    final streamedResponse = await request.send().timeout(timeoutDuration);
    developer.log(
      "✅ Request sent, waiting for response...",
      name: "ApiService",
    );

    final response = await http.Response.fromStream(streamedResponse);
    developer.log(
      "📥 Raw Response Status: ${response.statusCode}",
      name: "ApiService",
    );
    developer.log(
      "📥 Raw Response Headers: ${response.headers}",
      name: "ApiService",
    );
    developer.log("📥 Raw Response Body: ${response.body}", name: "ApiService");

    developer.log("🔄 Running response interceptors...", name: "ApiService");
    _runResponseInterceptors(response);

    developer.log("🔍 Handling response...", name: "ApiService");
    return _handleResponse(response);
  }

  static Future<http.Response> put(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    await ensureInitialized(); // ← CRITICAL: Wait for init
    await _ensureValidToken();
    final uri = _buildUri(endpoint);
    final request = http.Request('PUT', uri);
    request.headers.addAll(await authHeaders());
    request.body = json.encode(data);

    _runRequestInterceptors(request);
    final response = await http.Response.fromStream(
      await request.send().timeout(timeoutDuration),
    );
    _runResponseInterceptors(response);
    return _handleResponse(response);
  }

  static Future<http.Response> patch(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    await ensureInitialized(); // ← CRITICAL: Wait for init
    await _ensureValidToken();
    final uri = _buildUri(endpoint);
    final request = http.Request('PATCH', uri);
    request.headers.addAll(await authHeaders());
    request.body = json.encode(data);

    _runRequestInterceptors(request);
    final response = await http.Response.fromStream(
      await request.send().timeout(timeoutDuration),
    );
    _runResponseInterceptors(response);
    return _handleResponse(response);
  }

  static Future<http.Response> delete(String endpoint) async {
    await ensureInitialized(); // ← CRITICAL: Wait for init
    await _ensureValidToken();
    final uri = _buildUri(endpoint);
    final request = http.Request('DELETE', uri);
    request.headers.addAll(await authHeaders());
    _runRequestInterceptors(request);

    final response = await http.Response.fromStream(
      await request.send().timeout(timeoutDuration),
    );
    _runResponseInterceptors(response);
    return _handleResponse(response);
  }

  // === MULTIPART ===
  // ✅ Uploads (esp. video) can legitimately take much longer than the 30s
  // used for ordinary JSON requests. The video picker now allows up to
  // 5 minutes of footage (was 60s), which can be several hundred MB, so
  // this needs real headroom on a slow connection.
  static const Duration uploadTimeoutDuration = Duration(minutes: 10);

  static Future<http.Response> postMultipart(
    String endpoint, {
    Map<String, String>? fields,
    Map<String, String>? headers,
    List<http.MultipartFile>? files,
  }) async {
    await ensureInitialized(); // ← CRITICAL: Wait for init
    await _ensureValidToken();
    final uri = _buildUri(endpoint);

    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await authHeaders());
    if (headers != null) request.headers.addAll(headers);
    if (fields != null) request.fields.addAll(fields);
    if (files != null) request.files.addAll(files);

    _runRequestInterceptors(request);
    final streamed = await request.send().timeout(uploadTimeoutDuration);
    final response = await http.Response.fromStream(streamed);
    _runResponseInterceptors(response);

    return _handleResponse(response);
  }

  static Future<http.Response> patchMultipart(
    String endpoint, {
    Map<String, String>? fields,
    Map<String, String>? headers,
    List<http.MultipartFile>? files,
  }) async {
    await ensureInitialized(); // ← CRITICAL: Wait for init
    await _ensureValidToken();
    final uri = _buildUri(endpoint);

    final request = http.MultipartRequest('PATCH', uri);
    request.headers.addAll(await authHeaders());
    if (headers != null) request.headers.addAll(headers);
    if (fields != null) request.fields.addAll(fields);
    if (files != null) request.files.addAll(files);

    _runRequestInterceptors(request);
    final streamed = await request.send().timeout(uploadTimeoutDuration);
    final response = await http.Response.fromStream(streamed);
    _runResponseInterceptors(response);

    return _handleResponse(response);
  }

  // === INTERNAL HELPERS ===
  static Uri _buildUri(String endpoint, {Map<String, dynamic>? queryParams}) {
    var cleanEndpoint = endpoint.replaceAll(RegExp(r'^/+'), '');
    final url = _sanitizeUrl('$baseUrl/$_apiPrefix/$cleanEndpoint');
    developer.log(
      "🔗 Building URL from: baseUrl=$baseUrl, apiPrefix=$_apiPrefix, endpoint=$endpoint",
      name: "ApiService",
    );
    developer.log("🔗 Final URL: $url", name: "ApiService");
    var uri = Uri.parse(url);

    if (queryParams != null) {
      final queryParameters = {
        ...uri.queryParameters,
        ...queryParams.map((k, v) => MapEntry(k, v.toString())),
      };
      uri = uri.replace(queryParameters: queryParameters);
      developer.log("🔗 URL with query params: $uri", name: "ApiService");
    }
    return uri;
  }

  static String _sanitizeUrl(String url) {
    return url.replaceAll(RegExp(r'(?<!:)/+'), '/');
  }

  static Future<Map<String, String>> authHeaders() async {
    await ensureInitialized(); // Ensure we're initialized before accessing tokens

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
      developer.log(
        "🔑 Adding Authorization header with token",
        name: "ApiService",
      );
    } else {
      developer.log(
        "🔑 No auth token - skipping Authorization header",
        name: "ApiService",
      );
    }

    developer.log("📤 Auth headers generated: $headers", name: "ApiService");
    return headers;
  }

  static void _runRequestInterceptors(http.BaseRequest request) {
    developer.log(
      "🔄 Running ${requestInterceptors.length} request interceptors",
      name: "ApiService",
    );
    for (final interceptor in requestInterceptors) {
      interceptor(request);
    }
  }

  static void _runResponseInterceptors(http.Response response) {
    developer.log(
      "🔄 Running ${responseInterceptors.length} response interceptors",
      name: "ApiService",
    );
    for (final interceptor in responseInterceptors) {
      interceptor(response);
    }
  }

  static http.Response _handleResponse(http.Response response) {
    developer.log(
      "🔍 Handling response - Status: ${response.statusCode}",
      name: "ApiService",
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      developer.log(
        "✅ Request successful - Status: ${response.statusCode}",
        name: "ApiService",
      );
      return response;
    }

    developer.log(
      "❌ Request failed - Status: ${response.statusCode}",
      name: "ApiService",
    );
    final errorData = _tryParseError(response.body);
    developer.log("❌ Error details: $errorData", name: "ApiService");

    throw ApiException(
      statusCode: response.statusCode,
      message:
          errorData['message'] ??
          'Request failed with status ${response.statusCode}',
      details: errorData,
    );
  }

  static dynamic parseBody(http.Response response) {
    try {
      return json.decode(response.body);
    } catch (_) {
      return response.body;
    }
  }

  static Map<String, dynamic> _tryParseError(String body) {
    try {
      return json.decode(body) as Map<String, dynamic>;
    } catch (_) {
      return {
        'raw_response': body.length > 200
            ? '${body.substring(0, 200)}...'
            : body,
      };
    }
  }

  static Future<void> dispose() async {
    await _tokenStreamController.close();
    _refreshTimer?.cancel();
    _isInitialized = false;
    _initCompleter = null;
  }
}

/// 🔹 Request Interceptor Typedef
typedef RequestInterceptor = void Function(http.BaseRequest request);

/// 🔹 Response Interceptor Typedef
typedef ResponseInterceptor = void Function(http.Response response);

/// 🔹 API Exception Class
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic details;

  ApiException({required this.statusCode, required this.message, this.details});

  @override
  String toString() =>
      'ApiException: [$statusCode] $message${details != null ? ' - $details' : ''}';
}
