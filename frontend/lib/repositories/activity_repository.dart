import 'dart:convert';

import '../models/activity.dart';
import '../services/api_service.dart';

class ActivityRepository {
  /// Fetch recent activities from API
  /// Optionally pass [limit] to restrict number of results
  Future<List<Activity>> fetchRecentActivities({int limit = 10}) async {
    // ✅ No longer swallows failures into an empty list. ApiService.get
    // already throws ApiException on a non-2xx response (see
    // ApiService._handleResponse), which made the old `else` branch here
    // dead code — the real failure path was the catch-all below quietly
    // returning [], which is indistinguishable from "no activity yet".
    // Letting this propagate lets HomeScreen show a real "couldn't load"
    // state with a retry button instead of a misleading empty feed.
    final response = await ApiService.get(
      "activities/recent",
      queryParams: {"limit": limit},
      headers: {},
    );

    final Map<String, dynamic> decoded = json.decode(response.body);
    final List<dynamic> data = decoded["data"] ?? [];

    return data
        .map<Activity>(
          (jsonItem) => Activity.fromJson(jsonItem as Map<String, dynamic>),
        )
        .toList();
  }
}
