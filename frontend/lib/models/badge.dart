import 'package:flutter/material.dart';

/// Simple Badge model for profile achievements
class Badge {
  final String title; // Name of the badge (e.g., "Prayer Warrior")
  final IconData icon; // Badge icon
  final Color color; // Color for display

  const Badge({required this.title, required this.icon, required this.color});
}
