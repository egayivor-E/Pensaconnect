// lib/repositories/notification_repository.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/api_service.dart';

class NotificationRepository {
  /// Fetch notifications
  Future<List<AppNotification>> fetchNotifications() async {
    try {
      final response = await ApiService.get('notifications');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data
            .map<AppNotification>(
              (jsonItem) =>
                  AppNotification.fromJson(jsonItem as Map<String, dynamic>),
            )
            .toList();
      } else {
        debugPrint(
          "❌ Failed to load notifications: ${response.statusCode} - ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error fetching notifications: $e");
      return [];
    }
  }

  /// Update notification preferences on backend
  Future<bool> updateNotificationPreference(String token, bool enabled) async {
    try {
      final response = await ApiService.put('notifications/preferences', {
        "enabled": enabled,
      });

      if (response.statusCode == 200) {
        debugPrint("✅ Notification preference updated");
        return true;
      } else {
        debugPrint(
          "❌ Failed to update notification preference: "
          "${response.statusCode} - ${response.body}",
        );
        return false;
      }
    } catch (e) {
      debugPrint("❌ Error updating notification preference: $e");
      return false;
    }
  }
}
