import 'package:flutter/material.dart';

/// What the feed can actually *do* with a given Activity.targetType,
/// based on which backend endpoints and detail screens exist today:
///
/// | targetType      | like endpoint                  | detail screen        |
/// |------------------|--------------------------------|-----------------------|
/// | testimony         | POST /testimonies/:id/like     | /testimonies/:id      |
/// | forum_thread       | POST /threads/:id/react        | /threads/:id          |
/// | prayer_request     | POST /prayers/:id/toggle_prayer| (list only, no route) |
/// | post (forum post)  | POST /forums/posts/:id/like    | /posts/:id            |
/// | event               | none yet                      | none yet              |
///
/// Centralized here so the mapping only needs updating in one place as
/// more endpoints/screens are added — the feed card just asks "can I
/// like this?" / "can I open this?" instead of hardcoding target types.
class ActivityTargetInfo {
  final String label;
  final String activeLabel;
  final IconData icon;
  final IconData activeIcon;
  final Color activeColor;
  final bool canLike;
  final bool canOpenDetail;

  const ActivityTargetInfo({
    required this.label,
    required this.activeLabel,
    required this.icon,
    required this.activeIcon,
    required this.activeColor,
    required this.canLike,
    required this.canOpenDetail,
  });

  static const _none = ActivityTargetInfo(
    label: 'Like',
    activeLabel: 'Liked',
    icon: Icons.favorite_border,
    activeIcon: Icons.favorite,
    activeColor: Colors.redAccent,
    canLike: false,
    canOpenDetail: false,
  );
}

ActivityTargetInfo activityTargetInfo(String? targetType) {
  switch (targetType) {
    case 'testimony':
      return const ActivityTargetInfo(
        label: 'Like',
        activeLabel: 'Liked',
        icon: Icons.favorite_border,
        activeIcon: Icons.favorite,
        activeColor: Colors.redAccent,
        canLike: true,
        canOpenDetail: true,
      );
    case 'forum_thread':
      return const ActivityTargetInfo(
        label: 'Like',
        activeLabel: 'Liked',
        icon: Icons.thumb_up_outlined,
        activeIcon: Icons.thumb_up,
        activeColor: Colors.blueAccent,
        canLike: true,
        canOpenDetail: true,
      );
    case 'prayer_request':
      // Matches the "I prayed" affordance already used on the prayer
      // wall (favorite heart, red accent) so this reads the same way
      // wherever it shows up in the app.
      return const ActivityTargetInfo(
        label: 'I prayed',
        activeLabel: 'Prayed',
        icon: Icons.favorite_border,
        activeIcon: Icons.favorite,
        activeColor: Colors.redAccent,
        canLike: true,
        canOpenDetail: false,
      );
    case 'post':
      // A forum post shared to the Home feed. Uses the same like
      // endpoint as any other forum post (POST /forums/posts/:id/like)
      // and opens the dedicated post detail screen.
      return const ActivityTargetInfo(
        label: 'Like',
        activeLabel: 'Liked',
        icon: Icons.thumb_up_outlined,
        activeIcon: Icons.thumb_up,
        activeColor: Colors.blueAccent,
        canLike: true,
        canOpenDetail: true,
      );
    default:
      // Covers 'event' and null — no like/comment endpoint or detail
      // screen exists for these yet, so the card only offers Share.
      return ActivityTargetInfo._none;
  }
}
