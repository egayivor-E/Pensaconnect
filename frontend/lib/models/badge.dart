import 'package:flutter/material.dart';

/// Simple Badge model for profile achievements
class Badge {
  final String title; // Name of the badge (e.g., "Prayer Warrior")
  final IconData icon; // Badge icon
  final Color color; // Color for display

  const Badge({required this.title, required this.icon, required this.color});
}

/// Single source of truth for "what badges does someone have", given their
/// *own* real counts. Used by both the editable own-profile screen
/// (ProfileViewModel) and the read-only other-user profile screen
/// (UserProfileScreen) so a viewed user's badges are computed from their
/// actual prayers/testimonies/groups/join-date — not left blank, and not
/// accidentally computed from whoever is viewing the screen.
List<Badge> computeBadges({
  required int prayersCount,
  required int testimoniesCount,
  required int groupsCount,
  DateTime? createdAt,
}) {
  final badges = <Badge>[];

  if (prayersCount > 0) {
    badges.add(
      const Badge(
        title: "Prayer Warrior",
        icon: Icons.favorite,
        color: Colors.red,
      ),
    );
  }

  if (testimoniesCount > 0) {
    badges.add(
      const Badge(
        title: "Testifier",
        icon: Icons.record_voice_over,
        color: Colors.blue,
      ),
    );
  }

  if (groupsCount >= 3) {
    badges.add(
      const Badge(
        title: "Community Builder",
        icon: Icons.group,
        color: Colors.purple,
      ),
    );
  }

  if (prayersCount >= 50) {
    badges.add(
      const Badge(
        title: "Faithful Servant",
        icon: Icons.emoji_events,
        color: Colors.amber,
      ),
    );
  }

  if (createdAt != null) {
    badges.add(
      const Badge(title: "Pioneer", icon: Icons.star, color: Colors.green),
    );
  }

  return badges;
}
