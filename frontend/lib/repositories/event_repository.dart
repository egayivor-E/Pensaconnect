import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/event.dart';
import '../services/api_service.dart';

class EventRepository {
  /// Utility function to safely extract the list from the 'data' key of the API response
  List<Map<String, dynamic>> _extractListData(String responseBody) {
    try {
      final Map<String, dynamic> body = json.decode(responseBody);
      // Safely check if 'data' exists and is a List/Iterable
      final dynamic data = body["data"];

      if (data is Iterable) {
        // Correctly convert the Iterable (List<dynamic>) to List<Map<String, dynamic>>
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      debugPrint("❌ Error decoding or extracting data from response: $e");
      return [];
    }
  }

  /// Fetch all events
  Future<List<EventModel>> fetchAllEvents() async {
    try {
      final response = await ApiService.get('events', headers: {});

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);

        // This existing logic is correct for EventModel
        final List<dynamic> data = body["data"] ?? [];

        return data.map((e) => EventModel.fromJson(e)).toList();
      } else {
        debugPrint(
          "❌ Failed to fetch events: ${response.statusCode} - ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("❌ Error fetching events: $e");
      return [];
    }
  }

  // ... (addEvent, updateEvent, deleteEvent remain unchanged)

  /// Add a new event
  Future<bool> addEvent(EventModel event) async {
    try {
      final response = await ApiService.post('events', event.toJson());
      return response.statusCode == 201;
    } catch (e) {
      debugPrint("❌ Error adding event: $e");
      return false;
    }
  }

  /// Update an existing event
  Future<bool> updateEvent(EventModel event) async {
    try {
      final response = await ApiService.put(
        'events/${event.id}',
        event.toJson(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Error updating event: $e");
      return false;
    }
  }

  /// Delete event
  Future<bool> deleteEvent(String id) async {
    try {
      final response = await ApiService.delete('events/$id');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Error deleting event: $e");
      return false;
    }
  }

  // ------------------------------------------------------------------
  // 🎯 FIXED METHODS
  // ------------------------------------------------------------------

  /// Fetch attendees for an event
  Future<List<Map<String, dynamic>>> fetchAttendees(String eventId) async {
    try {
      final response = await ApiService.get(
        'events/$eventId/attendees',
        headers: {},
      );
      if (response.statusCode == 200) {
        // 🎯 Use the new safe extraction utility
        return _extractListData(response.body);
      }
      debugPrint("❌ Failed to fetch attendees: ${response.statusCode}");
      return [];
    } catch (e) {
      debugPrint("❌ Error fetching attendees: $e");
      return [];
    }
  }

  /// Fetch reminders for an event
  Future<List<Map<String, dynamic>>> fetchReminders(String eventId) async {
    try {
      final response = await ApiService.get(
        'events/$eventId/reminders',
        headers: {},
      );
      if (response.statusCode == 200) {
        // 🎯 Use the new safe extraction utility
        return _extractListData(response.body);
      }
      debugPrint("❌ Failed to fetch reminders: ${response.statusCode}");
      return [];
    } catch (e) {
      debugPrint("❌ Error fetching reminders: $e");
      return [];
    }
  }
}
