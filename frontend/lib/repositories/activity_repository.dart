import 'dart:convert';
import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../services/api_service.dart';

class ActivityRepository {
  /// Fetch recent activities from API
  /// Optionally pass [limit] to restrict number of results
  Future<List<Activity>> fetchRecentActivities({int limit = 10}) async {
    try {
      final response = await ApiService.get(
        "activities/recent",
        queryParams: {"limit": limit},
        headers: {},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = json.decode(response.body);

        // ✅ extract "data" safely
        final List<dynamic> data = decoded["data"] ?? [];

        return data
            .map<Activity>(
              (jsonItem) => Activity.fromJson(jsonItem as Map<String, dynamic>),
            )
            .toList();
      } else {
        debugPrint(
          "❌ Failed to load activities: ${response.statusCode} - ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error fetching activities: $e");
      return [];
    }
  }
}
