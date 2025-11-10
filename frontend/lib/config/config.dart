import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String get apiBaseUrl {
    final backend = dotenv.env['BACKEND_URL'] ?? '';
    final prefix = dotenv.env['API_PREFIX'] ?? '';
    if (backend.isEmpty) throw Exception('BACKEND_URL is not set in .env');
    return '$backend/$prefix';
  }
}

// config.dart
class AppConfig {
  static const String socketBaseUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://127.0.0.1:5000', // dev fallback
  );
}
