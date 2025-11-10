import 'dart:ui';
import 'package:intl/intl.dart'; // 👈 1. REQUIRED: Import the intl package
import 'package:flutter/foundation.dart'; // For debugPrint to work

class EventModel {
  final String id;
  final String title;
  final String description;
  final String eventType;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? location;
  final bool isVirtual;
  final String category;
  final bool isFeatured;
  final String? imageUrl;
  final int colorValue;
  final int? eventTypeId;

  EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.eventType,
    required this.startTime,
    required this.endTime,
    this.location,
    this.isVirtual = false,
    this.category = 'General',
    this.isFeatured = false,
    this.imageUrl,
    this.colorValue = 0xFF2196F3, // default blue color
    this.eventTypeId,
  });

  /// Use startTime as the main date
  DateTime? get date => startTime;

  /// Convert integer color value to Color
  Color get color => Color(colorValue);

  // 🛠️ THE CRITICAL FIX IS HERE
  factory EventModel.fromJson(Map<String, dynamic> json) {
    // Define the format exactly matching the server's string (excluding ' GMT')
    final DateFormat serverFormat = DateFormat('EEE, dd MMM yyyy HH:mm:ss');

    DateTime? parseDate(dynamic dateValue) {
      if (dateValue == null) return null;

      // Ensure the value is a string
      String dateString = dateValue.toString();

      // 2. Remove the problematic ' GMT' suffix and leading/trailing spaces
      String cleanDateString = dateString.replaceAll(' GMT', '').trim();

      try {
        // 3. Parse the clean string, treating it as UTC (true)
        // and converting it to the device's local time zone (.toLocal()).
        return serverFormat.parse(cleanDateString, true).toLocal();
      } catch (e) {
        // Log the error (e.g., the year '0001' entry) but prevent app crash
        debugPrint('Error parsing date "$dateString": $e');
        return null;
      }
    }

    return EventModel(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      eventType: json['event_type'] ?? 'general',
      // 4. Use the corrected date parsing function
      startTime: parseDate(json['start_time']),
      endTime: parseDate(json['end_time']),
      // ... rest of the fields
      location: json['location'],
      isVirtual: json['is_virtual'] ?? false,
      category: json['category'] ?? 'General',
      isFeatured: json['isFeatured'] ?? false,
      imageUrl: json['imageUrl'],
      colorValue: json['colorValue'] ?? 0xFF2196F3,
      eventTypeId: json['event_type_id'] != null
          ? int.tryParse(json['event_type_id'].toString())
          : null,
    );
  }

  // ... (Your existing toJson method remains the same)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'event_type': eventType,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'location': location,
      'is_virtual': isVirtual,
      'category': category,
      'isFeatured': isFeatured,
      'imageUrl': imageUrl,
      'colorValue': colorValue,
      'event_type_id': eventTypeId,
    };
  }
}
