import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../repositories/auth_repository.dart';
import '../models/user.dart';

class AppDrawer extends StatelessWidget {
  final void Function(int)? onItemTap;

  const AppDrawer({super.key, this.onItemTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isLargeScreen = MediaQuery.of(context).size.width >= 800;

    return Drawer(
      width: isLargeScreen ? 280 : null,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: const Text("Welcome to PensaConnect"),
            accountEmail: const Text("Ladies & Gents Wing"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.people_alt, color: Colors.white),
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              image: const DecorationImage(
                image: AssetImage('assets/images/drawer_bg.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.home,
                  title: 'Home',
                  index: 0,
                  route: '/home',
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.calendar_today,
                  title: 'Events',
                  route: '/events',
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.book,
                  title: 'Bible Study',
                  route: '/bible', // More consistent naming
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.music_note,
                  title: 'Praise & Worship',
                  route: '/worship', // More consistent naming
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.live_tv,
                  title: 'Live Stream',
                  route: '/live',
                ),
                _buildProtectedDrawerItem(
                  context,
                  icon: Icons.forum,
                  title: 'Discussion Forums',
                  route: '/forums',
                ),
                _buildProtectedDrawerItem(
                  context,
                  icon: Icons.self_improvement,
                  title: 'Prayer Wall',
                  route: '/prayer-wall',
                ),
                _buildProtectedDrawerItem(
                  context,
                  icon: Icons.auto_stories,
                  title: 'Testimonies',
                  route: '/testimonies',
                ),
                _buildProtectedDrawerItem(
                  context,
                  icon: Icons.chat,
                  title: 'Group Chats',
                  route: '/group-chats',
                ),
                const Divider(),
                _buildProtectedDrawerItem(
                  context,
                  icon: Icons.person,
                  title: 'My Profile',
                  route: '/profile',
                  requiresUserData: true,
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.settings,
                  title: 'Settings',
                  route: '/settings',
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.help,
                  title: 'Help & Support',
                  route: '/help-support',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'PensaConnect v1.0',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? route,
    int? index,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: theme.colorScheme.onSurface.withOpacity(0.65),
      ),
      title: Text(title),
      onTap: () => _handleNavigation(context, route: route, index: index),
    );
  }

  Widget _buildProtectedDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
    bool requiresUserData = false,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: theme.colorScheme.onSurface.withOpacity(0.65),
      ),
      title: Text(title),
      onTap: () async => _handleProtectedNavigation(
        context,
        route: route,
        requiresUserData: requiresUserData,
      ),
    );
  }

  // ✅ FIX: the drawer lists top-level *sections* (Home, Events, Bible
  // Study, ...), not drill-down detail screens — every tile is reachable
  // from every other page's drawer at any time. Pushing each tap onto the
  // Navigator stack meant hopping between sections a few times (very easy
  // to do from a persistent drawer) piled up duplicate pages endlessly, so
  // the back button had to walk back through every one of them one at a
  // time — the "looping" back behavior. Section switches now use go(),
  // which replaces the current location instead of stacking a new page on
  // top, so there's only ever one copy of each section in the history.
  bool _isCurrentRoute(BuildContext context, String route) {
    final currentLocation = GoRouterState.of(context).uri.toString();
    return currentLocation == route;
  }

  void _handleNavigation(BuildContext context, {String? route, int? index}) {
    // Close drawer if open
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    // Handle index-based navigation (if needed)
    if (index != null && onItemTap != null) {
      onItemTap!(index);
    }

    // Handle route-based navigation — no-op if already on that section.
    if (route != null && !_isCurrentRoute(context, route)) {
      context.go(route);
    }
  }

  Future<void> _handleProtectedNavigation(
    BuildContext context, {
    required String route,
    bool requiresUserData = false,
  }) async {
    // Close drawer first
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    if (_isCurrentRoute(context, route)) return;

    final authRepo = context.read<AuthRepository>();
    final user = await authRepo.getCurrentUser();

    if (user == null) {
      if (context.mounted) _showLoginPrompt(context);
      return;
    }

    if (!context.mounted) return;

    if (requiresUserData) {
      context.go(route, extra: user);
    } else {
      context.go(route);
    }
  }

  void _showLoginPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login Required'),
        content: const Text('Please log in to access this feature.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/login');
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }
}
