// lib/repositories/notification_repository.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/api_service.dart';

class NotificationRepository {
  /// Fetch notifications for the current user.
  ///
  /// The backend wraps every response as {status, message, data} (see
  /// success_response() in backend/api/v1/utils.py) — this used to be
  /// decoded as if `data` were a bare top-level list, which meant every
  /// call silently failed to map over the wrapper dict instead.
  Future<List<AppNotification>> fetchNotifications({int page = 1}) async {
    try {
      final response = await ApiService.get(
        'notifications',
        queryParams: {'page': page.toString()},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final List<dynamic> data = body['data'] ?? [];
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

  /// Fetch the unread notification count, used for the home screen bell badge.
  Future<int> fetchUnreadCount() async {
    try {
      final response = await ApiService.get('notifications/unread-count');
      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          return (data['count'] as num?)?.toInt() ?? 0;
        }
        return 0;
      }
      debugPrint(
        "❌ Failed to fetch unread count: ${response.statusCode} - ${response.body}",
      );
      return 0;
    } catch (e) {
      debugPrint("❌ Error fetching unread count: $e");
      return 0;
    }
  }

  /// Mark a single notification as read.
  Future<bool> markAsRead(String notificationId) async {
    try {
      final response = await ApiService.post(
        'notifications/$notificationId/read',
        const {},
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Error marking notification $notificationId as read: $e");
      return false;
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
