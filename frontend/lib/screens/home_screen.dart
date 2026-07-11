import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() {
  runApp(const SocialFeedApp());
}

class SocialFeedApp extends StatelessWidget {
  const SocialFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Polished Social Feed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const SocialFeedScreen(),
    );
  }
}

// ==========================================
// DOMAIN MODELS & TYPE SAFETY
// ==========================================

class HomeFeature {
  final IconData icon;
  final String title;
  final String route;
  final Color color;

  const HomeFeature({
    required this.icon,
    required this.title,
    required this.route,
    required this.color,
  });
}

class Activity {
  final String id;
  final String authorId;
  final String authorName;
  final String? avatarUrl;
  final String content;
  final String targetType;
  final String targetId;
  final int likeCount;
  final bool isLiked;

  const Activity({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.avatarUrl,
    required this.content,
    required this.targetType,
    required this.targetId,
    required this.likeCount,
    required this.isLiked,
  });

  String get heroTag => 'avatar_${targetType}_$targetId';

  Activity copyWith({
    String? content,
    int? likeCount,
    bool? isLiked,
  }) {
    return Activity(
      id: id,
      authorId: authorId,
      authorName: authorName,
      avatarUrl: avatarUrl,
      content: content ?? this.content,
      targetType: targetType,
      targetId: targetId,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

class UserProfile {
  final String id;
  final String name;
  final String email;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
  });
}

// ==========================================
// MAIN SCREEN & STATE MANAGEMENT
// ==========================================

class SocialFeedScreen extends StatefulWidget {
  const SocialFeedScreen({super.key});

  @override
  State<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends State<SocialFeedScreen> {
  static const List<HomeFeature> _features = [
    HomeFeature(
      icon: Icons.calendar_today,
      title: 'Events',
      route: '/events',
      color: Colors.blue,
    ),
    HomeFeature(
      icon: Icons.group,
      title: 'Community',
      route: '/community',
      color: Colors.teal,
    ),
    HomeFeature(
      icon: Icons.article,
      title: 'Articles',
      route: '/articles',
      color: Colors.orange,
    ),
  ];

  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  Timer? _debounce; // FIX: debounce search input instead of filtering per keystroke

  UserProfile? _currentUser;
  List<Activity> _allActivities = [];
  List<Activity> _filteredActivities = [];

  bool _isLoading = true;
  bool _hasError = false; // FIX: surface fetch failures instead of hanging forever
  final Set<String> _pendingLikes = {};

  @override
  void initState() {
    super.initState();
    _initialLoad();
    _searchQuery.addListener(_applyFilter);
  }

  Future<void> _initialLoad() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      await Future.wait([
        _loadUserProfile(),
        _fetchActivities(),
      ]);
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserProfile() async {
    await Future.delayed(const Duration(milliseconds: 600));
    _currentUser = const UserProfile(
      id: 'usr_me',
      name: 'Alex Developer',
      email: 'alex@example.com',
    );
  }

  Future<void> _handleRefresh() async {
    try {
      await _fetchActivities();
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  Future<void> _fetchActivities() async {
    await Future.delayed(const Duration(milliseconds: 800));

    final fetchedData = <Activity>[
      const Activity(
        id: 'act_101',
        authorId: 'usr_552',
        authorName: 'David K.',
        avatarUrl:
            'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&auto=format&fit=crop&q=80',
        content:
            'Just deployed the new real-time WebSocket messaging service! Performance is up by 40%.',
        targetType: 'post',
        targetId: 'post_8891',
        likeCount: 24,
        isLiked: false,
      ),
      const Activity(
        id: 'act_102',
        authorId: 'usr_312',
        authorName: 'Sarah Jenkins',
        avatarUrl:
            'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150&auto=format&fit=crop&q=80',
        content:
            'Anyone attending the Flutter architectural meetup this Saturday? Let’s connect!',
        targetType: 'event',
        targetId: 'evt_4022',
        likeCount: 56,
        isLiked: true,
      ),
      const Activity(
        id: 'act_103',
        authorId: 'usr_789',
        authorName: 'Marcus Chen',
        avatarUrl:
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&auto=format&fit=crop&q=80',
        content:
            'Written a comprehensive guide on moving from Material 2 to Material 3 in large-scale apps.',
        targetType: 'article',
        targetId: 'art_9011',
        likeCount: 112,
        isLiked: false,
      ),
    ];

    if (mounted) {
      setState(() {
        _allActivities = fetchedData;
        _filteredActivities = _computeFiltered(_allActivities, _searchQuery.value);
      });
    }
  }

  // Pure filter logic, no setState here — callers decide when to rebuild.
  List<Activity> _computeFiltered(List<Activity> source, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return List.from(source);
    return source.where((act) {
      final contentMatch = act.content.toLowerCase().contains(query);
      final authorMatch = act.authorName.toLowerCase().contains(query);
      return contentMatch || authorMatch;
    }).toList();
  }

  // Triggered by the ValueNotifier listener (debounced search changes).
  void _applyFilter() {
    setState(() {
      _filteredActivities = _computeFiltered(_allActivities, _searchQuery.value);
    });
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchQuery.value = text; // triggers _applyFilter via the listener
    });
  }

  // FIX: single setState, no nested call into _applyFilter's own setState.
  Future<void> _handleLike(Activity activity) async {
    if (_pendingLikes.contains(activity.id)) return;

    setState(() {
      _pendingLikes.add(activity.id);
      final index = _allActivities.indexWhere((a) => a.id == activity.id);
      if (index != -1) {
        final current = _allActivities[index];
        _allActivities[index] = current.copyWith(
          isLiked: !current.isLiked,
          likeCount:
              current.isLiked ? current.likeCount - 1 : current.likeCount + 1,
        );
        _filteredActivities = _computeFiltered(_allActivities, _searchQuery.value);
      }
    });

    try {
      await Future.delayed(const Duration(milliseconds: 400));
    } finally {
      if (mounted) {
        setState(() => _pendingLikes.remove(activity.id));
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Feed'),
        actions: [
          if (_currentUser != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  _currentUser!.name.isNotEmpty ? _currentUser!.name[0] : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFeatureBanner(),
          _buildSearchField(),
          Expanded(
            child: _isLoading
                ? _buildShimmerSkeleton()
                : _hasError
                    ? _buildErrorState()
                    : RefreshIndicator(
                        onRefresh: _handleRefresh,
                        child: _filteredActivities.isEmpty
                            ? _buildAnimatedEmptyState()
                            : _buildFeedList(),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('New Post'),
        elevation: 2,
      ),
    );
  }

  Widget _buildFeatureBanner() {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _features.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final feature = _features[index];
          return ActionChip(
            avatar: Icon(feature.icon, size: 18, color: feature.color),
            label: Text(feature.title),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Navigating to ${feature.route}')),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, value, child) {
          return TextField(
            controller: _searchController,
            onChanged: _onSearchChanged, // FIX: debounced
            decoration: InputDecoration(
              hintText: 'Search feed...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _debounce?.cancel();
                        _searchController.clear();
                        _searchQuery.value = '';
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredActivities.length,
      physics: const AlwaysScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final activity = _filteredActivities[index];
        return _ActivityCard(
          key: ValueKey(activity.id), // FIX: stable identity across reorders
          activity: activity,
          isPending: _pendingLikes.contains(activity.id),
          onLike: () => _handleLike(activity),
        )
            .animate()
            .fadeIn(duration: 300.ms, delay: (50 * index).ms)
            .slideY(begin: 0.08, end: 0, curve: Curves.easeOutQuad);
      },
    );
  }

  Widget _buildShimmerSkeleton() {
    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        itemBuilder: (context, index) {
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(radius: 20),
                      const SizedBox(width: 12),
                      Container(width: 140, height: 16, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(width: double.infinity, height: 14, color: Colors.grey),
                  const SizedBox(height: 8),
                  Container(width: 220, height: 14, color: Colors.grey),
                  const SizedBox(height: 16),
                  Container(width: 60, height: 20, color: Colors.grey),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.explore_off_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            )
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1.05, 1.05),
                  duration: 1500.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 16),
            Text(
              'No activities found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ).animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search terms.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: retry UI when initial load fails, instead of an infinite skeleton.
  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Couldn’t load your feed',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _initialLoad,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// MATERIAL 3 ACTIVITY CARD COMPONENT
// ==========================================

class _ActivityCard extends StatefulWidget {
  final Activity activity;
  final bool isPending;
  final VoidCallback onLike;

  const _ActivityCard({
    super.key,
    required this.activity,
    required this.isPending,
    required this.onLike,
  });

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burstController;
  late final Animation<double> _burstScale;

  @override
  void initState() {
    super.initState();
    // FIX: a proper "burst and settle back to 1.0" heart animation,
    // instead of a tween that has no way back down.
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _burstScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_burstController);
  }

  @override
  void didUpdateWidget(covariant _ActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.activity.isLiked && widget.activity.isLiked) {
      _burstController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _burstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activity = widget.activity;
    final hasAvatar = (activity.avatarUrl ?? '').isNotEmpty;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerLow,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Hero(
                  tag: activity.heroTag,
                  child: ClipOval(
                    child: hasAvatar
                        ? CachedNetworkImage(
                            imageUrl: activity.avatarUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.person, size: 20),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: theme.colorScheme.primaryContainer,
                              child: Icon(
                                Icons.person,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          )
                        : Container(
                            width: 40,
                            height: 40,
                            color: theme.colorScheme.primaryContainer,
                            child: Icon(
                              Icons.person,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.authorName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Posted in ${activity.targetType.toUpperCase()}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              activity.content,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                AnimatedBuilder(
                  animation: _burstScale,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _burstScale.value,
                      child: child,
                    );
                  },
                  child: Opacity(
                    // NEW: visible pending state instead of a silent no-op tap
                    opacity: widget.isPending ? 0.5 : 1.0,
                    child: IconButton(
                      icon: widget.isPending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              activity.isLiked ? Icons.favorite : Icons.favorite_border,
                              color: activity.isLiked
                                  ? Colors.redAccent
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                      onPressed: widget.isPending ? null : widget.onLike,
                    ),
                  ),
                ),
                Text(
                  '${activity.likeCount}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
