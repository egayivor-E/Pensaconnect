// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/activity.dart';
import '../providers/auth_provider.dart';
import '../repositories/activity_repository.dart';
import '../repositories/forum_repository.dart';
import '../repositories/prayer_repository.dart';
import '../repositories/testimony_repository.dart';
import '../theme/app_style.dart';
import '../utils/activity_target.dart';
import '../widgets/app_drawer.dart';

// ==========================================
// DOMAIN MODEL
// ==========================================

class HomeFeature {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Color color;

  const HomeFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.color,
  });
}

// ==========================================
// HOME SCREEN
// ==========================================
//
// NOTE: this file previously contained an entire standalone demo app
// (its own `main()`, `MaterialApp`, and mock `Activity`/`UserProfile`
// models) that wasn't wired into PensaConnect's actual routing or
// AuthProvider at all — none of its "feature" taps went to real
// screens. This rebuild replaces that with a real dashboard that
// greets the logged-in member and links to the app's actual routes.

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ActivityRepository _activityRepo = ActivityRepository();

  List<Activity> _activities = [];
  bool _loadingActivities = true;
  bool _activitiesFailed = false;

  // Tracks activities whose like/prayer action is mid-flight, so a
  // double-tap can't fire the request twice.
  final Set<int> _actionInFlight = {};
  // Tracks the *locally known* liked/prayed state per activity id. The
  // recent-activity feed doesn't carry a likedByMe flag from the API (it's
  // a log entry, not the underlying testimony/thread/prayer itself), so
  // this reflects "did the current session already toggle this" rather
  // than server truth — good enough to give the button visual feedback.
  final Map<int, bool> _locallyActive = {};

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    setState(() {
      _loadingActivities = true;
      _activitiesFailed = false;
    });

    try {
      final fetched = await _activityRepo.fetchRecentActivities(limit: 10);

      // ✅ De-duplicate by the activity's own id. Using a Map keyed by id
      // (rather than just setState-appending to the existing list) means
      // a pull-to-refresh — or any rebuild that re-triggers this — always
      // *replaces* the feed with a clean, unique set instead of piling
      // more copies of the same rows on top of what's already showing.
      final unique = <int, Activity>{};
      for (final activity in fetched) {
        unique[activity.id] = activity;
      }

      if (!mounted) return;
      setState(() {
        _activities = unique.values.toList();
        _loadingActivities = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingActivities = false;
        _activitiesFailed = true;
      });
    }
  }

  Future<void> _handleActivityAction(Activity activity) async {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canLike || activity.targetId == null) return;
    if (_actionInFlight.contains(activity.id)) return;

    setState(() => _actionInFlight.add(activity.id));

    try {
      // ✅ Route the action through the *real* endpoint for whatever this
      // activity is about, reusing the same repositories the actual
      // testimony/forum/prayer screens use — so tapping it here has the
      // same effect as tapping it there, instead of the feed just
      // toggling a fake local flag.
      switch (activity.targetType) {
        case 'testimony':
          await context.read<TestimonyRepository>().toggleLike(
            activity.targetId!,
          );
          break;
        case 'forum_thread':
          await context.read<ForumRepository>().toggleLikeThread(
            activity.targetId!,
          );
          break;
        case 'prayer_request':
          await context.read<PrayerRepository>().togglePrayerById(
            activity.targetId!,
          );
          break;
      }

      if (!mounted) return;
      setState(() {
        _locallyActive[activity.id] = !(_locallyActive[activity.id] ?? false);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t complete "${info.label}". Try again.')),
      );
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(activity.id));
    }
  }

  void _openActivityTarget(Activity activity) {
    switch (activity.targetType) {
      case 'testimony':
        context.push('/testimonies/${activity.targetId}');
        break;
      case 'forum_thread':
        context.push('/threads/${activity.targetId}');
        break;
    }
  }

  static const List<HomeFeature> _features = [
    HomeFeature(
      icon: Icons.calendar_today,
      title: 'Events',
      subtitle: "What's coming up",
      route: '/events',
      color: AppColors.emberGold,
    ),
    HomeFeature(
      icon: Icons.book,
      title: 'Bible Study',
      subtitle: 'Grow in the Word',
      route: '/bible',
      color: AppColors.verdantSage,
    ),
    HomeFeature(
      icon: Icons.music_note,
      title: 'Praise & Worship',
      subtitle: 'Songs to lift you',
      route: '/worship',
      color: AppColors.roseQuartz,
    ),
    HomeFeature(
      icon: Icons.live_tv,
      title: 'Live Stream',
      subtitle: 'Join the gathering',
      route: '/live',
      color: AppColors.inkDusk,
    ),
    HomeFeature(
      icon: Icons.forum,
      title: 'Discussion Forums',
      subtitle: 'Talk it through',
      route: '/forums',
      color: AppColors.verdantSage,
    ),
    HomeFeature(
      icon: Icons.self_improvement,
      title: 'Prayer Wall',
      subtitle: 'Ask, and be asked for',
      route: '/prayer-wall',
      color: AppColors.emberGold,
    ),
    HomeFeature(
      icon: Icons.auto_stories,
      title: 'Testimonies',
      subtitle: 'Stories of faith',
      route: '/testimonies',
      color: AppColors.roseQuartz,
    ),
    HomeFeature(
      icon: Icons.chat,
      title: 'Group Chats',
      subtitle: 'Stay connected',
      route: '/group-chats',
      color: AppColors.inkDusk,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final username = authProvider.currentUser?.username;
    final greetingName = (username == null || username.isEmpty)
        ? 'friend'
        : username;

    return Scaffold(
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _loadActivities,
        child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            backgroundColor: AppColors.inkDusk,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.inkDusk, AppColors.emberGold],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Welcome back, $greetingName',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PensaConnect · Ladies & Gents Wing',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.98,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _FeatureCard(feature: _features[index]),
                childCount: _features.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Activity', style: theme.textTheme.titleLarge),
                  if (!_loadingActivities)
                    IconButton(
                      onPressed: _loadActivities,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                    ),
                ],
              ),
            ),
          ),
          _buildActivitySliver(theme),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        ),
      ),
    );
  }

  Widget _buildActivitySliver(ThemeData theme) {
    if (_loadingActivities) {
      return const SliverPadding(
        padding: EdgeInsets.symmetric(vertical: 32),
        sliver: SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_activitiesFailed) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: Column(
              children: [
                Text(
                  "Couldn't load recent activity.",
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loadActivities,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_activities.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: Text(
              'Nothing new yet — check back soon.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      sliver: SliverList(
        // ✅ Keyed by the activity's own id so Flutter's element diffing
        // matches list items to the correct widget state across rebuilds
        // (e.g. after an action toggles _locallyActive) instead of
        // matching by position, which is what causes rows to visually
        // "jump" or duplicate state when the underlying list changes.
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final activity = _activities[index];
            final isLast = index == _activities.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: _ActivityTile(
                key: ValueKey(activity.id),
                activity: activity,
                isActionInFlight: _actionInFlight.contains(activity.id),
                isLocallyActive: _locallyActive[activity.id] ?? false,
                onAction: () => _handleActivityAction(activity),
                onOpen: () => _openActivityTarget(activity),
              ),
            );
          },
          childCount: _activities.length,
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Activity activity;
  final bool isActionInFlight;
  final bool isLocallyActive;
  final VoidCallback onAction;
  final VoidCallback onOpen;

  const _ActivityTile({
    super.key,
    required this.activity,
    required this.isActionInFlight,
    required this.isLocallyActive,
    required this.onAction,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = activityTargetInfo(activity.targetType);

    return Material(
      color: theme.cardTheme.color,
      shape: AppShapes.archBorder(top: 16, bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: info.canOpenDetail ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              activity.hasAuthorAvatar
                  ? CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(activity.authorAvatarUrl!),
                    )
                  : CircleAvatar(
                      radius: 20,
                      backgroundColor: activity.color.withOpacity(0.15),
                      child: Icon(activity.icon, color: activity.color, size: 20),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (activity.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        activity.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (activity.authorName != null) activity.authorName!,
                        activity.timeAgo,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
              ),
              if (info.canLike)
                IconButton(
                  onPressed: isActionInFlight ? null : onAction,
                  tooltip: isLocallyActive ? info.activeLabel : info.label,
                  icon: isActionInFlight
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isLocallyActive ? info.activeIcon : info.icon,
                          color: isLocallyActive
                              ? info.activeColor
                              : theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final HomeFeature feature;

  const _FeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardTheme.color,
      shape: AppShapes.archBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(feature.route),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: feature.color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(feature.icon, color: feature.color, size: 22),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(feature.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    feature.subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
