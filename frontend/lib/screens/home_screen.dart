import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart'
    show FontAwesome;
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:pensaconnect/services/api_service.dart';
import 'package:pensaconnect/services/auth_service.dart';

import '../config/config.dart';
import '../widgets/app_drawer.dart';
import '../widgets/chat_options_sheet.dart';
import '../repositories/activity_repository.dart';
import '../repositories/user_repository.dart';
import '../models/activity.dart';
import '../models/user.dart';

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

  // ✅ Debounce search input instead of filtering on every keystroke —
  // filtering itself is cheap here, but this avoids a rebuild per
  // keystroke on a screen with animated list items, which otherwise
  // restarts their entrance animation on every character typed.
  Timer? _searchDebounce;

  // ✅ Distinguishes "the request actually failed" from "you're logged
  // out" / "nothing to show yet" — previously both looked identical
  // (empty feed, no explanation, no way to retry).
  bool _hasError = false;

  // ✅ FIX: track which user's data is currently loaded, and listen for
  // AuthService changes so this screen stays in sync across login/logout
  // even if it isn't recreated (e.g. it's still mounted underneath a
  // pushed route when the auth state changes).
  int? _loadedForUserId;
  late final VoidCallback _authListener;

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
    setState(() {
      _loading = true;
      _hasError = false;
    });

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
        // ✅ This is a genuine failure (network error, server error,
        // etc.) — not just "nobody's logged in." Surface it distinctly
        // so the empty-state UI can offer a retry instead of silently
        // looking like a quiet, empty feed.
        _hasError = true;
        _loadedForUserId = AuthService().userId;
      });
    }
  }

  // ✅ Debounced search — updates the query 300ms after the user stops
  // typing, instead of on every keystroke.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
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
    _searchDebounce?.cancel();
    _searchController.dispose();
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

    if (_currentUser!.profilePicture == null) {
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

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: _currentUser!.getProfilePictureUrl(Config.baseUrl),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        placeholder: (context, url) => CircleAvatar(
          radius: 20,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: 20,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.person,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return StatefulBuilder(
      // Local StatefulBuilder just to redraw the clear (X) button as text
      // changes, without tying the whole screen's rebuild to every
      // keystroke (the actual filter still only updates after debounce).
      builder: (context, setLocalState) {
        return TextField(
          controller: _searchController,
          onChanged: (value) {
            setLocalState(() {});
            _onSearchChanged(value);
          },
          decoration: InputDecoration(
            hintText: 'Search...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchDebounce?.cancel();
                      _searchController.clear();
                      setLocalState(() {});
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
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
      },
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

  Widget _buildActivityCard(BuildContext context, Activity activity, {Key? key}) {
    final theme = Theme.of(context);
    final resolvedAvatarUrl = _resolveAvatarUrl(activity.authorAvatarUrl);

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prefer a real author avatar; fall back to the activity-type
            // icon circle when no author image is available. Keeps every
            // card visually anchored to a person, not just an event type.
            activity.hasAuthorAvatar
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: resolvedAvatarUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 44,
                        height: 44,
                        color: activity.color.withOpacity(0.12),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: activity.color.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(activity.icon, color: activity.color, size: 22),
                      ),
                    ),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (activity.authorName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        activity.authorName!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.55),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Text(
                    activity.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activity.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activity.timeAgo,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  // ✅ Shimmer skeleton instead of a bare centered spinner — gives the
  // person an immediate sense of the page's shape (quick actions row +
  // a few feed cards) rather than a blank screen with a spinner floating
  // in the middle of it.
  Widget _buildLoadingSkeleton(ThemeData theme) {
    return Shimmer.fromColors(
      baseColor: theme.colorScheme.onSurface.withOpacity(0.06),
      highlightColor: theme.colorScheme.onSurface.withOpacity(0.12),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(width: 220, height: 22, color: Colors.white),
          const SizedBox(height: 8),
          Container(width: 160, height: 14, color: Colors.white),
          const SizedBox(height: 20),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(width: 44, height: 10, color: Colors.white),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(width: 140, height: 20, color: Colors.white),
          const SizedBox(height: 16),
          for (int i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }

  // ✅ Real failure state (network/server error) with a retry — separate
  // from the "no activity yet" empty state, which is a normal condition
  // rather than a problem.
  Widget _buildErrorFeedState(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 36,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't load your feed",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Check your connection and try again.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _loadData,
            child: const Text("Retry"),
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
            // ⚠️ No notifications screen/route exists yet — this used to
            // silently do nothing on tap, which looks broken. Until a
            // real destination exists, at least confirm the tap happened.
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notifications are coming soon'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
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
          ? _buildLoadingSkeleton(theme)
          : Row(
              children: [
                if (isLargeScreen) const AppDrawer(),
                Expanded(
                  child: Container(
                    color: theme.colorScheme.surface,
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
                                      // ⚠️ Same as the notifications bell —
                                      // no "all activity" screen exists yet.
                                      // Honest feedback beats a dead tap.
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'A full activity history is coming soon',
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      },
                                      child: const Text("See all"),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: _hasError && filteredActivities.isEmpty
                                ? SliverToBoxAdapter(
                                    child: _buildErrorFeedState(context, theme),
                                  )
                                : filteredActivities.isEmpty
                                ? SliverToBoxAdapter(
                                    child: _buildEmptyFeedState(context, theme),
                                  )
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final activity = filteredActivities[index];
                                        return _buildActivityCard(
                                          context,
                                          activity,
                                          // ✅ Stable-ish key: Activity has
                                          // no id field from the backend,
                                          // so derive one from content +
                                          // timestamp rather than using the
                                          // volatile list index alone.
                                          key: ValueKey(
                                            '${activity.title}_${activity.createdAt.millisecondsSinceEpoch}_$index',
                                          ),
                                        )
                                            .animate()
                                            .fadeIn(
                                              duration: 280.ms,
                                              delay: (40 * index).ms,
                                            )
                                            .slideY(
                                              begin: 0.08,
                                              end: 0,
                                              curve: Curves.easeOutQuad,
                                            );
                                      },
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
