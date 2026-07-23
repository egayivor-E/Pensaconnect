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
/// [knownUsername]/[knownProfilePicture]: whatever the tapped widget
/// already had in memory (a message's sender name, a member list row's
/// photo, etc). ✅ FIX ("avatar tap loads before opening the profile"):
/// passing these seeds UserProfileScreen's cache right before navigating,
/// so its header paints immediately on the very first tap instead of
/// showing a full loading skeleton while it waits on a network round
/// trip — see UserRepository.seedProfileCache for why this never
/// overwrites a fuller, already-fetched profile.
void openUserProfile(
  BuildContext context,
  int? userId, {
  String? knownUsername,
  String? knownProfilePicture,
}) {
  if (userId == null) return;

  final currentUserId = context.read<AuthProvider>().currentUser?.id;
  if (currentUserId != null && currentUserId == userId) {
    context.go('/profile');
    return;
  }

  UserRepository.seedProfileCache(
    userId: userId,
    username: knownUsername,
    profilePicture: knownProfilePicture,
  );
  context.push('/profile/$userId');
}
