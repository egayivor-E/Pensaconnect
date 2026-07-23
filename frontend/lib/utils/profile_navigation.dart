import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../repositories/user_repository.dart';

/// Central place for "tap an avatar → go to that person's profile" logic,
/// used by [UserAvatar] and anywhere else that needs it directly (e.g. a
/// username label next to an avatar).
///
/// - Tapping your *own* avatar opens the full, editable `/profile` screen.
/// - Tapping anyone else's avatar pushes the read-only `/profile/:userId`
///   screen (see screens/user_profile_screen.dart) so the back button
///   returns to wherever you tapped from, instead of replacing it.
///
/// Pass [username]/[profilePicture] whenever the tap site already knows
/// them (a post's author, a chat message's sender, a member row, etc.) —
/// they're used to prime UserProfileScreen's cache (see
/// UserRepository.primeProfilePreview) so the profile's header paints
/// immediately on the very first tap instead of showing a full-screen
/// spinner while the real fetch is still in flight.
void openUserProfile(
  BuildContext context,
  int? userId, {
  String? username,
  String? profilePicture,
}) {
  if (userId == null) return;

  final currentUserId = context.read<AuthProvider>().currentUser?.id;
  if (currentUserId != null && currentUserId == userId) {
    context.go('/profile');
    return;
  }

  if (username != null && username.isNotEmpty) {
    UserRepository.primeProfilePreview(
      userId,
      username: username,
      profilePicture: profilePicture,
    );
  }
  context.push('/profile/$userId');
}
