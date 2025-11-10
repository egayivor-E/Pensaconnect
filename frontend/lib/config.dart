import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String backendUrl =
      dotenv.env['BACKEND_URL'] ?? 'http://127.0.0.1:5000';
  static String apiPrefix = dotenv.env['API_PREFIX'] ?? 'api/v1';
}
