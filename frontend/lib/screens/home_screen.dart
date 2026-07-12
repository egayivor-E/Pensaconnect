import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
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
  bool _activitiesFailed = false;

  // Tracks which user's data is currently loaded, and listens for
  // AuthService changes so this screen stays in sync across login/logout
  // even if it isn't recreated (e.g. it's still mounted underneath a
  // pushed route when the auth state changes).
  int? _loadedForUserId;
  late final VoidCallback _authListener;

  // --- Feed engagement ---
  // Keyed by the activity's own id (not identity hash) so state survives
  // search filtering *and* so ValueKey-based list diffing and this map
  // agree on what identifies a row.
  final Set<int> _likedActivityKeys = {};
  // Guards against a fast double-tap firing two toggle requests before
  // the first one resolves.
  final Set<int> _actionInFlight = {};
  int? _heartBurstKey;
  Timer? _heartBurstTimer;

  static const List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.calendar_today_rounded,
      'title': 'Events',
      'route': '/events',
      'color': Color(0xFF3B82F6),
    },
    {
      'icon': Icons.menu_book_rounded,
      'title': 'Bible Study',
      'route': '/bible',
      'color': Color(0xFF10B981),
    },
    {
      'icon': Icons.music_note_rounded,
      'title': 'Worship',
      'route': '/worship',
      'color': Color(0xFFA855F7),
    },
    {
      'icon': Icons.live_tv_rounded,
      'title': 'Live',
      'route': '/live',
      'color': Color(0xFFEF4444),
    },
    {
      'icon': Icons.forum_rounded,
      'title': 'Discussions',
      'route': '/forums',
      'color': Color(0xFFF97316),
    },
    {
      'icon': Icons.self_improvement_rounded,
      'title': 'Prayer Wall',
      'route': '/prayer-wall',
      'color': Color(0xFF14B8A6),
    },
    {
      'icon': Icons.auto_stories_rounded,
      'title': 'Testimonies',
      'route': '/testimonies',
      'color': Color(0xFFEC4899),
    },
    {
      'icon': Icons.chat_bubble_rounded,
      'title': 'Group Chats',
      'route': '/group-chats',
      'color': Color(0xFF6366F1),
    },
  ];

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
      debugPrint(
        '🔄 HomeScreen: auth changed ($_loadedForUserId → $newUserId), reloading',
      );
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _activitiesFailed = false;
    });

    final loggedInUserId = AuthService().userId;
    User? user;
    List<Activity> activities = [];
    bool activitiesFailed = false;

    // ✅ Uses the actual token source (ApiService/secure storage), not
    // SharedPreferences['auth_token'] — nothing ever wrote a token
    // there, so that lookup was always null and getCurrentUser() never
    // ran with real credentials.
    final token = await ApiService.getToken();

    if (token != null && loggedInUserId != null) {
      // Profile and activity feed are fetched independently so a
      // failure in one doesn't take down the other — e.g. a slow/broken
      // profile endpoint shouldn't blank out an otherwise-working feed.
      try {
        user = await UserRepository().getCurrentUser(token);
      } catch (e) {
        debugPrint('⚠️ HomeScreen: failed to load profile: $e');
      }

      try {
        final fetched = await ActivityRepository().fetchRecentActivities(
          limit: 20,
        );
        // De-duplicate by id so a rebuild/refresh that re-triggers this
        // never piles duplicate rows into the feed.
        final unique = <int, Activity>{};
        for (final a in fetched) {
          unique[a.id] = a;
        }
        activities = unique.values.toList();
      } catch (e) {
        debugPrint('❌ HomeScreen: failed to load activities: $e');
        activitiesFailed = true;
      }
    } else {
      debugPrint('⚠️ HomeScreen: no valid session, skipping activity fetch');
    }

    if (!mounted) return;
    setState(() {
      _currentUser = user;
      _activities = activities;
      _activitiesFailed = activitiesFailed;
      _loading = false;
      _loadedForUserId = loggedInUserId;
    });
  }

  @override
  void dispose() {
    AuthService().removeListener(_authListener);
    _searchController.dispose();
    _heartBurstTimer?.cancel();
    super.dispose();
  }

  Widget _buildProfileAvatar(ThemeData theme) {
    if (_currentUser == null) {
      return CircleAvatar(
        radius: 19,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.person,
          color: theme.colorScheme.onPrimaryContainer,
          size: 20,
        ),
      );
    }

    return CircleAvatar(
      radius: 19,
      backgroundColor: theme.colorScheme.primaryContainer,
      backgroundImage: _currentUser!.profilePicture != null
          ? NetworkImage(_currentUser!.getProfilePictureUrl(Config.baseUrl))
          : null,
      onBackgroundImageError: (exception, stackTrace) {
        debugPrint('Profile image load error: $exception');
      },
      child: _currentUser!.profilePicture == null
          ? Icon(
              Icons.person,
              color: theme.colorScheme.onPrimaryContainer,
              size: 20,
            )
          : null,
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search features & activity',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.4),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: theme.colorScheme.onSurface.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  // Compact quick-action chip used in the horizontal row that replaces
  // a full-page icon grid — same feature data, much lower visual weight
  // so the activity feed can be the star of the screen.
  Widget _buildQuickAction(BuildContext context, Map<String, dynamic> feature) {
    final theme = Theme.of(context);
    final color = feature['color'] as Color;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push(feature['route'] as String),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Icon(feature['icon'] as IconData, color: color, size: 25),
              ),
              const SizedBox(height: 6),
              Text(
                feature['title'] as String,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Activity author avatars come back as a relative path (same as
  // User.profile_picture), not a full URL — resolve against
  // Config.baseUrl the same way _buildProfileAvatar does for the
  // current user.
  String? _resolveAvatarUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = Config.baseUrl.endsWith('/')
        ? Config.baseUrl.substring(0, Config.baseUrl.length - 1)
        : Config.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  // Opens the real content an activity refers to, when we have somewhere
  // to send the user — testimony and forum_thread both have live detail
  // screens; prayer_request doesn't (yet), so tapping does nothing for
  // those rather than dead-ending on a broken route.
  void _openActivityTarget(Activity activity) {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canOpenDetail || activity.targetId == null) return;

    switch (activity.targetType) {
      case 'testimony':
        context.push('/testimonies/${activity.targetId}');
        break;
      case 'forum_thread':
        context.push(
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
  Future<void> _handleLike(Activity activity) async {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canLike || activity.targetId == null) return;
    if (_actionInFlight.contains(activity.id)) return;

    final wasLiked = _likedActivityKeys.contains(activity.id);
    setState(() {
      _actionInFlight.add(activity.id);
      wasLiked
          ? _likedActivityKeys.remove(activity.id)
          : _likedActivityKeys.add(activity.id);
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
        wasLiked
            ? _likedActivityKeys.add(activity.id)
            : _likedActivityKeys.remove(activity.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't save that — check your connection and try again.",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(activity.id));
    }
  }

  void _handleDoubleTapLike(Activity activity) {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canLike) return;
    if (!_likedActivityKeys.contains(activity.id)) {
      _handleLike(activity);
    }
    _heartBurstTimer?.cancel();
    setState(() => _heartBurstKey = activity.id);
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
    final isDark = theme.brightness == Brightness.dark;
    final resolvedAvatarUrl = _resolveAvatarUrl(activity.authorAvatarUrl);
    final info = activityTargetInfo(activity.targetType);
    final isLiked = _likedActivityKeys.contains(activity.id);
    final isInFlight = _actionInFlight.contains(activity.id);
    final showBurst = _heartBurstKey == activity.id;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.08 : 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
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
                        child: Icon(
                          activity.icon,
                          color: activity.color,
                          size: 22,
                        ),
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
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5),
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
            onTap: () => _openActivityTarget(activity),
            onDoubleTap: () => _handleDoubleTapLike(activity),
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
                IgnorePointer(
                  child: AnimatedScale(
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  if (info.canLike)
                    Expanded(
                      child: _ActionBarButton(
                        icon: isLiked ? info.activeIcon : info.icon,
                        label: isLiked ? info.activeLabel : info.label,
                        color: isLiked ? info.activeColor : null,
                        highlighted: isLiked,
                        loading: isInFlight,
                        onTap: isInFlight ? null : () => _handleLike(activity),
                      ),
                    ),
                  if (info.canOpenDetail)
                    Expanded(
                      child: _ActionBarButton(
                        icon: Icons.mode_comment_outlined,
                        label: 'Comment',
                        onTap: () => _openActivityTarget(activity),
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
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: _ActionBarButton(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () => _shareActivity(activity),
              ),
            ),
          const SizedBox(height: 2),
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
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 36,
            color: theme.colorScheme.primary.withOpacity(0.6),
          ),
          const SizedBox(height: 12),
          Text(
            "Your feed is just getting started",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Join a discussion, post a prayer request, or check today's devotional — activity from your community will show up here.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => context.push('/forums'),
            child: const Text("Explore Discussions"),
          ),
        ],
      ),
    );
  }

  // Distinct from the empty state — a failed fetch shouldn't read as
  // "nothing has happened yet", it should read as "we couldn't get it".
  Widget _buildFeedErrorState(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 34,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't load recent activity",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
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
          OutlinedButton(onPressed: _loadData, child: const Text('Try again')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isLargeScreen = MediaQuery.of(context).size.width >= 800;
    final bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    final filteredFeatures = _features
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
        title: const Text('PensaConnect'),
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () {},
            tooltip: 'Notifications',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: GestureDetector(
              onTap: () => context.go('/profile'),
              child: _buildProfileAvatar(theme),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: isLargeScreen ? null : const AppDrawer(),
      body: Row(
        children: [
          if (isLargeScreen) const AppDrawer(),
          Expanded(
            child: Container(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    // --- iOS has no AppBar, so its identity/notifications/
                    // profile access lives inline instead of disappearing. ---
                    if (isIOS)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'PensaConnect',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.notifications_none_rounded,
                                ),
                                onPressed: () {},
                                tooltip: 'Notifications',
                              ),
                              GestureDetector(
                                onTap: () => context.go('/profile'),
                                child: _buildProfileAvatar(theme),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // --- Greeting header ---
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentUser != null
                                  ? 'Welcome back, ${_currentUser!.username}!'
                                  : 'Welcome back!',
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

                    // --- Search ---
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: _buildSearchField(theme),
                      ),
                    ),

                    // --- Quick-actions row ---
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 20),
                      sliver: SliverToBoxAdapter(
                        child: SizedBox(
                          height: 92,
                          child: _loading
                              ? const _QuickActionsSkeleton()
                              : filteredFeatures.isEmpty
                              ? Center(
                                  child: Text(
                                    'No matching features',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.5),
                                        ),
                                  ),
                                )
                              : ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: filteredFeatures.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) =>
                                      _buildQuickAction(
                                        context,
                                        filteredFeatures[index],
                                      ),
                                ),
                        ),
                      ),
                    ),

                    // --- Activity feed: the primary content ---
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Recent Activity',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: _buildFeedSliver(theme, filteredActivities),
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

  Widget _buildFeedSliver(ThemeData theme, List<Activity> filteredActivities) {
    if (_loading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: EdgeInsets.only(bottom: index == 2 ? 0 : 14),
            child: const _ActivitySkeletonCard(),
          ),
          childCount: 3,
        ),
      );
    }

    if (_activitiesFailed) {
      return SliverToBoxAdapter(
        child: _buildFeedErrorState(context, theme),
      );
    }

    if (filteredActivities.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyFeedState(context, theme),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final activity = filteredActivities[index];
          final isLast = index == filteredActivities.length - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: _FadeSlideIn(
              delay: Duration(milliseconds: 40 * index.clamp(0, 6)),
              child: KeyedSubtree(
                key: ValueKey(activity.id),
                child: _buildActivityCard(context, activity),
              ),
            ),
          );
        },
        childCount: filteredActivities.length,
      ),
    );
  }
}

// ==========================================
// FEED ENTRANCE ANIMATION
// ==========================================

/// Small fade + upward-slide wrapper so feed cards ease in rather than
/// popping onto the screen — with a slight per-index stagger, the whole
/// list reads as one deliberate motion instead of a static dump of rows.
class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _FadeSlideIn({required this.child, this.delay = Duration.zero});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ==========================================
// SHIMMER LOADING SKELETONS
// ==========================================

class _QuickActionsSkeleton extends StatelessWidget {
  const _QuickActionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) => SizedBox(
          width: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _SkeletonBlock(width: 56, height: 56, radius: 28),
              SizedBox(height: 8),
              _SkeletonBlock(width: 44, height: 10, radius: 5),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivitySkeletonCard extends StatelessWidget {
  const _ActivitySkeletonCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Shimmer(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SkeletonBlock(width: 44, height: 44, radius: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SkeletonBlock(width: 120, height: 12, radius: 6),
                      SizedBox(height: 8),
                      _SkeletonBlock(width: 90, height: 10, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _SkeletonBlock(width: double.infinity, height: 12, radius: 6),
            const SizedBox(height: 8),
            const _SkeletonBlock(width: 180, height: 12, radius: 6),
            const SizedBox(height: 16),
            const _SkeletonBlock(width: double.infinity, height: 1, radius: 0),
            const SizedBox(height: 10),
            Row(
              children: const [
                Expanded(child: _SkeletonBlock(height: 14, radius: 6)),
                SizedBox(width: 16),
                Expanded(child: _SkeletonBlock(height: 14, radius: 6)),
                SizedBox(width: 16),
                Expanded(child: _SkeletonBlock(height: 14, radius: 6)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBlock({
    this.width = double.infinity,
    required this.height,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Sweeps a soft highlight band left-to-right across its child on a loop.
/// Implemented with a plain `AnimationController` + `ShaderMask` so it has
/// no dependency beyond Flutter itself.
class _Shimmer extends StatefulWidget {
  final Widget child;

  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withOpacity(0.08);
    final highlight = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.16);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment(-1 - t * 3, 0),
              end: Alignment(1 - t * 3, 0),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ==========================================
// ACTION BAR BUTTON
// ==========================================

/// Single Like/Comment/Share button used in the activity card's action
/// bar. Pulled out as its own widget so all of them stay pixel-identical
/// (equal width, same icon size, same tap target) the way FB/IG action
/// bars do. When `highlighted` is true, it fills with a soft tint of
/// `color` so an active state is legible at a glance, not just from the
/// icon swap.
class _ActionBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool highlighted;
  final bool loading;
  final VoidCallback? onTap;

  const _ActionBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.highlighted = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor =
        color ?? theme.colorScheme.onSurface.withOpacity(0.65);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: highlighted
                  ? effectiveColor.withOpacity(0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: effectiveColor,
                    ),
                  )
                else
                  AnimatedScale(
                    scale: highlighted ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Icon(icon, size: 20, color: effectiveColor),
                  ),
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
        ),
      ),
    );
  }
}
