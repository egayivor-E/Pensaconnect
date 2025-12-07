import 'package:flutter/material.dart';
import '../models/user.dart';
import '../repositories/user_repository.dart';

class UserAvatar extends StatelessWidget {
  final String? profilePicture;
  final String? username;
  final double size;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.profilePicture,
    this.username,
    this.size = 40.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = UserRepository.getProfilePictureUrl(profilePicture);

    return GestureDetector(
      onTap: onTap,
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
      size: size,
    );
  }
}
