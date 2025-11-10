import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

class Activity {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final DateTime createdAt;

  Activity({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.createdAt,
  });

  /// Returns a "5m ago" style string
  String get timeAgo => timeago.format(createdAt);

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      title: json['title'] ?? 'Untitled',
      subtitle: json['subtitle'] ?? '',
      icon: _mapIcon(json['icon']),
      color: _mapColor(json['color']),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'subtitle': subtitle,
      'icon': icon.codePoint,
      'color': color.value,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Maps string from API to Flutter IconData
  static IconData _mapIcon(String? iconName) {
    switch (iconName) {
      case 'groups':
        return Icons.groups;
      case 'event':
        return Icons.event;
      case 'book':
        return FontAwesome.book;
      default:
        return Icons.notifications;
    }
  }

  /// Maps string from API to Flutter Color
  static Color _mapColor(String? colorName) {
    switch (colorName) {
      case 'teal':
        return Colors.teal;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'red':
        return Colors.red;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
