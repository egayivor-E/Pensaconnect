import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    final hasPicture = profilePicture != null && profilePicture!.isNotEmpty;

    // Decode at the size the avatar is actually shown at — an avatar
    // photo can be a multi-megapixel upload, and without a memory-cache
    // hint Flutter decodes it at full resolution every time even though
    // it's rendered as a 40px circle. Multiply by devicePixelRatio so it
    // still looks sharp on high-DPI screens.
    final cacheDimension =
        (size * MediaQuery.devicePixelRatioOf(context)).round();

    return GestureDetector(
      onTap:
          onTap ??
          (userId != null ? () => openUserProfile(context, userId) : null),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: hasPicture
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: cacheDimension,
                  memCacheHeight: cacheDimension,
                  placeholder: (context, url) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.person, size: size * 0.6, color: Colors.white),
                  ),
                )
              : Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.person, size: size * 0.6, color: Colors.white),
                ),
        ),
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
