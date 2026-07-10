import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart'
    show FontAwesome;
import 'package:go_router/go_router.dart';
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
  Widget _buildActivityCard(BuildContext context, Activity activity) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Prefer a real author avatar; fall back to the activity-type
              // icon circle when no author image is available. Keeps every
              // card visually anchored to a person, not just an event type.
              activity.hasAuthorAvatar
                  ? CircleAvatar(
                      radius: 22,
                      backgroundColor: activity.color.withOpacity(0.12),
                      backgroundImage: NetworkImage(activity.authorAvatarUrl!),
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
