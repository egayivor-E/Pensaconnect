import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart'
    show FontAwesome;
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pensaconnect/services/api_service.dart';
import 'package:pensaconnect/services/auth_service.dart';

import '../config/config.dart';
import '../widgets/app_drawer.dart';
import '../widgets/chat_options_sheet.dart';
import '../repositories/activity_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/testimony_repository.dart';
import '../repositories/forum_repository.dart';
import '../repositories/prayer_repository.dart';
import '../models/activity.dart';
import '../models/user.dart';
import '../utils/activity_target.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  User? _currentUser;
  List<Activity> _activities = [];
  bool _loading = true;

  // ✅ FIX: track which user's data is currently loaded, and listen for
  // AuthService changes so this screen stays in sync across login/logout
  // even if it isn't recreated (e.g. it's still mounted underneath a
  // pushed route when the auth state changes).
  int? _loadedForUserId;
  late final VoidCallback _authListener;

  // --- Feed engagement ---
  // Which activities the current user has liked/prayed for *this session*.
  // Keyed by identityHashCode(activity) so it survives search filtering
  // without needing a dedicated id on the feed's Activity objects. This
  // is optimistic UI state layered on top of real API calls (see
  // _handleLike) — the feed doesn't currently re-fetch each target's
  // true like state on load, so a like made from another screen won't
  // show as already-active here until the user taps it again.
  final Set<int> _likedActivityKeys = {};
  int? _heartBurstKey;
  Timer? _heartBurstTimer;

  @override
  void initState() {
    super.initState();
    _authListener = _onAuthChanged;
    AuthService().addListener(_authListener);
    _loadData();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final newUserId = AuthService().userId;

    // Only reload if the logged-in user actually changed (covers both
    // "logged out" -> null and "different user logged in" -> new id).
    if (newUserId != _loadedForUserId) {
      debugPrint('🔄 HomeScreen: auth changed ($_loadedForUserId → $newUserId), reloading');
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // ✅ FIX: use the actual token source (ApiService/secure storage),
      // not SharedPreferences['auth_token'] — nothing ever wrote a token
      // there, so `token` was always null and getCurrentUser() never ran
      // with real credentials.
      final token = await ApiService.getToken();
      final loggedInUserId = AuthService().userId;

      User? user;
      List<Activity> activities = [];

      if (token != null && loggedInUserId != null) {
        // Fetch user + activities together; only proceed with activities
        // if we're actually authenticated, so we don't fire a request
        // that's guaranteed to 401 (e.g. right after a logout).
        user = await UserRepository().getCurrentUser(token);
        activities = await ActivityRepository().fetchRecentActivities(limit: 20);
      } else {
        debugPrint('⚠️ HomeScreen: no valid session, skipping activity fetch');
      }

      if (!mounted) return;
      setState(() {
        _currentUser = user;
        _activities = activities;
        _loading = false;
        _loadedForUserId = loggedInUserId;
      });
    } catch (e) {
      debugPrint("❌ Error in _loadData: $e");
      if (!mounted) return;
      setState(() {
        _currentUser = null;
        _activities = [];
        _loading = false;
        _loadedForUserId = AuthService().userId;
      });
    }
  }

  // Kept for potential future grid usages (e.g. a "see all" features page).
  int getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4;
    if (width > 800) return 3;
    if (width > 600) return 2;
    return 2;
  }

  double getChildAspectRatio(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 800) return 1.2;
    return 0.9;
  }

  @override
  void dispose() {
    AuthService().removeListener(_authListener);
    _searchController.dispose();
    _heartBurstTimer?.cancel();
    super.dispose();
  }

  Widget _buildProfileAvatar() {
    if (_currentUser == null) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          Icons.person,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          size: 20,
        ),
      );
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: _currentUser!.profilePicture != null
          ? NetworkImage(
              _currentUser!.getProfilePictureUrl(Config.baseUrl),
            )
          : null,
      onBackgroundImageError: (exception, stackTrace) {
        debugPrint('Profile image load error: $exception');
      },
      child: _currentUser!.profilePicture == null
          ? Icon(
              Icons.person,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 20,
            )
          : null,
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        hintText: 'Search...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: theme.colorScheme.surface.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 16,
        ),
      ),
    );
  }

  // Compact quick-action chip used in the horizontal row that replaces
  // the old full-page icon grid. Same feature data, much lower visual
  // weight so the activity feed can be the star of the screen.
  Widget _buildQuickAction(BuildContext context, Map<String, dynamic> feature) {
    final theme = Theme.of(context);
    final color = feature['color'] as Color;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => GoRouter.of(context).push(feature['route'] as String),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(feature['icon'] as IconData, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 68,
              child: Text(
                feature['title'] as String,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Feed-style card for a single activity item — richer than a plain
  // ListTile so the "Recent Activity" section reads as living content,
  // not a settings-style list.
  // Activity author avatars come back as a relative path (same as
  // User.profile_picture), not a full URL — resolve against Config.baseUrl
  // the same way _buildProfileAvatar does for the current user.
  String? _resolveAvatarUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = Config.baseUrl.endsWith('/')
        ? Config.baseUrl.substring(0, Config.baseUrl.length - 1)
        : Config.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  // Opens the real content an activity refers to, when we have somewhere
  // to send the user — testimony and forum_thread both have live detail
  // screens; prayer_request/post/event don't (yet), so tapping does
  // nothing for those rather than dead-ending on a broken route.
  void _openActivityTarget(BuildContext context, Activity activity) {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canOpenDetail || activity.targetId == null) return;

    switch (activity.targetType) {
      case 'testimony':
        GoRouter.of(context).push('/testimonies/${activity.targetId}');
        break;
      case 'forum_thread':
        GoRouter.of(context).push(
          '/threads/${activity.targetId}',
          extra: {'title': activity.title},
        );
        break;
    }
  }

  // Routes a like to whichever real endpoint backs this activity's
  // target — there's no "like an activity" endpoint, because an
  // Activity is a log entry, not content of its own. Optimistically
  // flips the heart, then rolls back if the API call fails.
  Future<void> _handleLike(Activity activity, int key) async {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canLike || activity.targetId == null) return;

    final wasLiked = _likedActivityKeys.contains(key);
    setState(() {
      wasLiked ? _likedActivityKeys.remove(key) : _likedActivityKeys.add(key);
    });

    try {
      switch (activity.targetType) {
        case 'testimony':
          await TestimonyRepository().toggleLike(activity.targetId!);
          break;
        case 'forum_thread':
          await ForumRepository().toggleLikeThread(activity.targetId!);
          break;
        case 'prayer_request':
          await PrayerRepository().togglePrayerById(activity.targetId!);
          break;
      }
    } catch (e) {
      debugPrint(
        '❌ Failed to sync like for ${activity.targetType}#${activity.targetId}: $e',
      );
      if (!mounted) return;
      setState(() {
        wasLiked ? _likedActivityKeys.add(key) : _likedActivityKeys.remove(key);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save that — check your connection and try again."),
        ),
      );
    }
  }

  void _handleDoubleTapLike(Activity activity, int key) {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canLike) return;
    if (!_likedActivityKeys.contains(key)) {
      _handleLike(activity, key);
    }
    _heartBurstTimer?.cancel();
    setState(() => _heartBurstKey = key);
    _heartBurstTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _heartBurstKey = null);
    });
  }

  void _shareActivity(Activity activity) {
    final text = activity.subtitle.isNotEmpty
        ? '${activity.title}\n\n${activity.subtitle}'
        : activity.title;
    Share.share(text);
  }

  // Feed-style post card — header (author identity), content, then a
  // real Like/Comment/Share action bar. Like and Comment only render
  // when the activity has a real backing object with a working endpoint
  // (see ActivityTargetInfo) — Share always works since it just shares
  // the activity's own text.
  Widget _buildActivityCard(BuildContext context, Activity activity) {
    final theme = Theme.of(context);
    final resolvedAvatarUrl = _resolveAvatarUrl(activity.authorAvatarUrl);
    final key = identityHashCode(activity);
    final info = activityTargetInfo(activity.targetType);
    final isLiked = _likedActivityKeys.contains(key);
    final showBurst = _heartBurstKey == key;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Post header: avatar, author, meta ---
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                activity.hasAuthorAvatar
                    ? CircleAvatar(
                        radius: 22,
                        backgroundColor: activity.color.withOpacity(0.12),
                        backgroundImage: NetworkImage(resolvedAvatarUrl!),
                        onBackgroundImageError: (exception, stackTrace) {
                          debugPrint('Activity avatar load error: $exception');
                        },
                      )
                    : Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: activity.color.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(activity.icon, color: activity.color, size: 22),
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.authorName ?? activity.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(activity.icon, size: 12, color: activity.color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              activity.timeAgo,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- Post content: tap opens the real content (if any),
          // double-tap likes it (if likeable) ---
          GestureDetector(
            onTap: () => _openActivityTarget(context, activity),
            onDoubleTap: () => _handleDoubleTapLike(activity, key),
            behavior: HitTestBehavior.opaque,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activity.authorName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            activity.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Text(
                        activity.subtitle,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.75),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedScale(
                  scale: showBurst ? 1.0 : 0.6,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: showBurst ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      info.activeIcon,
                      color: Colors.white,
                      size: 72,
                      shadows: const [
                        Shadow(color: Colors.black38, blurRadius: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (info.canLike || info.canOpenDetail) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outline.withOpacity(0.1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  if (info.canLike)
                    Expanded(
                      child: _ActionBarButton(
                        icon: isLiked ? info.activeIcon : info.icon,
                        label: isLiked ? info.activeLabel : info.label,
                        color: isLiked ? info.activeColor : null,
                        onTap: () => _handleLike(activity, key),
                      ),
                    ),
                  if (info.canOpenDetail)
                    Expanded(
                      child: _ActionBarButton(
                        icon: Icons.mode_comment_outlined,
                        label: 'Comment',
                        onTap: () => _openActivityTarget(context, activity),
                      ),
                    ),
                  Expanded(
                    child: _ActionBarButton(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: () => _shareActivity(activity),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: _ActionBarButton(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () => _shareActivity(activity),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // Empty state that invites action instead of just announcing absence —
  // avoids the "nobody uses this app" impression a bare "No recent
  // activity" text creates.
  Widget _buildEmptyFeedState(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome,
            size: 36,
            color: theme.colorScheme.primary.withOpacity(0.6),
          ),
          const SizedBox(height: 12),
          Text(
            "Your feed is just getting started",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Join a discussion, post a prayer request, or check today's devotional — activity from your community will show up here.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => GoRouter.of(context).push('/forums'),
            child: const Text("Explore Discussions"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isLargeScreen = MediaQuery.of(context).size.width >= 800;
    final bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    final features = [
      {
        'icon': Icons.calendar_today,
        'title': 'Events',
        'route': '/events',
        'color': Colors.blue,
        'description': 'View upcoming church events',
      },
      {
        'icon': Icons.book,
        'title': 'Bible Study',
        'route': '/bible',
        'color': Colors.green,
        'description': 'Daily devotionals & study plans',
      },
      {
        'icon': Icons.music_note,
        'title': 'Praise & Worship',
        'route': '/worship',
        'color': Colors.purple,
        'description': 'Worship songs & playlists',
      },
      {
        'icon': Icons.live_tv,
        'title': 'Live Stream',
        'route': '/live',
        'color': Colors.red,
        'description': 'Join live services',
      },
      {
        'icon': Icons.forum,
        'title': 'Discussions',
        'route': '/forums',
        'color': Colors.orange,
        'description': 'Connect with others',
      },
      {
        'icon': FontAwesome.play,
        'title': 'Prayer Wall',
        'route': '/prayer-wall',
        'color': Colors.teal,
        'description': 'Share prayer requests',
      },
    ];

    final filteredFeatures = features
        .where(
          (f) => (f['title'] as String).toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();

    final filteredActivities = _activities
        .where(
          (a) => a.title.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    PreferredSizeWidget? appBar;
    if (!isIOS) {
      appBar = AppBar(
        title: const Text("PensaConnect"),
        actions: [
          SizedBox(
            width: 250,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: _buildSearchField(theme),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {},
            tooltip: 'Notifications',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: GestureDetector(
              onTap: () => GoRouter.of(context).go('/profile'),
              child: _buildProfileAvatar(),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: isLargeScreen ? null : const AppDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                if (isLargeScreen) const AppDrawer(),
                Expanded(
                  child: Container(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      child: CustomScrollView(
                        slivers: [
                          // --- Greeting header ---
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Welcome back, ${_currentUser?.username ?? "Friend"}!",
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Here's what's happening in your community",
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // --- Compact quick-actions row (was the full grid) ---
                          if (filteredFeatures.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.only(top: 20),
                              sliver: SliverToBoxAdapter(
                                child: SizedBox(
                                  height: 92,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    itemCount: filteredFeatures.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                                    itemBuilder: (context, index) {
                                      try {
                                        return _buildQuickAction(
                                          context,
                                          filteredFeatures[index],
                                        );
                                      } catch (e) {
                                        debugPrint('Error rendering quick action: $e');
                                        return const SizedBox(width: 68);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),

                          // --- Activity feed: now the primary content ---
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Recent Activity",
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (filteredActivities.isNotEmpty)
                                    TextButton(
                                      onPressed: () {},
                                      child: const Text("See all"),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: filteredActivities.isEmpty
                                ? SliverToBoxAdapter(
                                    child: _buildEmptyFeedState(context, theme),
                                  )
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) => _buildActivityCard(
                                        context,
                                        filteredActivities[index],
                                      ),
                                      childCount: filteredActivities.length,
                                    ),
                                  ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (context) => const ChatOptionsSheet(),
          );
        },
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.chat_bubble, color: Colors.white),
      ),
    );
  }
}

// Single Like/Comment/Share button used in the activity card's action
// bar. Pulled out as its own widget so all of them stay pixel-identical
// (equal width, same icon size, same tap target) the way FB/IG action
// bars do.
class _ActionBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurface.withOpacity(0.65);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: effectiveColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: effectiveColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
