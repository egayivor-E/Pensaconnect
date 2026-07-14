import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Central place for "tap an avatar → go to that person's profile" logic,
/// used by [UserAvatar] and anywhere else that needs it directly (e.g. a
/// username label next to an avatar).
///
/// - Tapping your *own* avatar opens the full, editable `/profile` screen.
/// - Tapping anyone else's avatar pushes the read-only `/profile/:userId`
///   screen (see screens/user_profile_screen.dart) so the back button
///   returns to wherever you tapped from, instead of replacing it.
void openUserProfile(BuildContext context, int? userId) {
  if (userId == null) return;

  final currentUserId = context.read<AuthProvider>().currentUser?.id;
  if (currentUserId != null && currentUserId == userId) {
    context.go('/profile');
  } else {
    context.push('/profile/$userId');
  }
}
