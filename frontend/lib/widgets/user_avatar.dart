import 'package:flutter/material.dart';
import '../models/user.dart';
import '../repositories/user_repository.dart';
import '../utils/profile_navigation.dart';

class UserAvatar extends StatelessWidget {
  final String? profilePicture;
  final String? username;
  final double size;

  /// Whose profile tapping this avatar should open. Leave null only for
  /// avatars that genuinely aren't tied to a real user (e.g. a system/bot
  /// message) — everywhere else, pass the post/message/member's author id
  /// so the avatar is clickable "no matter where it's used."
  final int? userId;

  /// Overrides the default "go to this user's profile" tap behavior, for
  /// the rare screen that needs something else to happen on tap instead.
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.profilePicture,
    this.username,
    this.size = 40.0,
    this.userId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = UserRepository.getProfilePictureUrl(profilePicture);

    return GestureDetector(
      onTap:
          onTap ??
          (userId != null ? () => openUserProfile(context, userId) : null),
      child: CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(imageUrl),
        onBackgroundImageError: (exception, stackTrace) {
          debugPrint('Failed to load avatar: $exception');
        },
        child: profilePicture == null || profilePicture!.isEmpty
            ? Icon(Icons.person, size: size * 0.6, color: Colors.white)
            : null,
      ),
    );
  }
}

// Usage with User object:
class UserProfileAvatar extends StatelessWidget {
  final User user;
  final double size;

  const UserProfileAvatar({super.key, required this.user, this.size = 40.0});

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      profilePicture: user.profilePicture,
      username: user.username,
      userId: user.id,
      size: size,
    );
  }
}
