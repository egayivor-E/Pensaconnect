import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter_animate/flutter_animate.dart';

// [Point 1] Removed unused import: 'package:flutter/foundation.dart' show defaultTargetPlatform;

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

// [Point 2] Strongly-typed HomeFeature class replacing Map<String, dynamic>
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

// [Point 9] Server-backed Activity model with embedded like state
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

  // [Point 8] Reliable, collision-free Hero tag handling nulls safely
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
  // [Point 3] Moved static features outside build() to prevent reallocation on rebuild
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
  // [Point 5] ValueNotifier isolates search text state from the main widget tree
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  
  UserProfile? _currentUser;
  List<Activity> _allActivities = [];
  // [Point 4] Filtered list stored as state property, updated only when query changes
  List<Activity> _filteredActivities = [];
  
  bool _isLoading = true;
  // [Point 10] Track pending network likes to prevent rapid multi-tap spam
  final Set<String> _pendingLikes = {};

  @override
  void initState() {
    super.initState();
    _initialLoad();
    _searchQuery.addListener(_applyFilter);
  }

  // [Point 11] Initial load fetches BOTH user and activities
  Future<void> _initialLoad() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadUserProfile(),
      _fetchActivities(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
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

  // [Point 11] Refresh indicator ONLY reloads activities; user data remains untouched
  Future<void> _handleRefresh() async {
    await _fetchActivities();
  }

  Future<void> _fetchActivities() async {
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Realistic mock data
    final fetchedData = [
      const Activity(
        id: 'act_101',
        authorId: 'usr_552',
        authorName: 'David K.',
        avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&auto=format&fit=crop&q=80',
        content: 'Just deployed the new real-time WebSocket messaging service! Performance is up by 40%.',
        targetType: 'post',
        targetId: 'post_8891',
        likeCount: 24,
        isLiked: false,
      ),
      const Activity(
        id: 'act_102',
        authorId: 'usr_312',
        authorName: 'Sarah Jenkins',
        avatarUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150&auto=format&fit=crop&q=80',
        content: 'Anyone attending the Flutter architectural meetup this Saturday? Let’s connect!',
        targetType: 'event',
        targetId: 'evt_4022',
        likeCount: 56,
        isLiked: true,
      ),
      const Activity(
        id: 'act_103',
        authorId: 'usr_789',
        authorName: 'Marcus Chen',
        avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&auto=format&fit=crop&q=80',
        content: 'Written a comprehensive guide on moving from Material 2 to Material 3 in large-scale apps.',
        targetType: 'article',
        targetId: 'art_9011',
        likeCount: 112,
        isLiked: false,
      ),
    ];

    if (mounted) {
      _allActivities = fetchedData;
      _applyFilter();
    }
  }

  // [Point 4 & 12] Trim whitespace, lowercase, and update filtered state directly
  void _applyFilter() {
    final query = _searchQuery.value.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredActivities = List.from(_allActivities);
      } else {
        _filteredActivities = _allActivities.where((act) {
          final contentMatch = act.content.toLowerCase().contains(query);
          final authorMatch = act.authorName.toLowerCase().contains(query);
          return contentMatch || authorMatch;
        }).toList();
      }
    });
  }

  // [Point 10] Network request throttling with optimistic UI updates
  Future<void> _handleLike(Activity activity) async {
    if (_pendingLikes.contains(activity.id)) return;

    setState(() {
      _pendingLikes.add(activity.id);
      
      // Optimistic state toggle
      final index = _allActivities.indexWhere((a) => a.id == activity.id);
      if (index != -1) {
        final current = _allActivities[index];
        _allActivities[index] = current.copyWith(
          isLiked: !current.isLiked,
          likeCount: current.isLiked ? current.likeCount - 1 : current.likeCount + 1,
        );
        _applyFilter();
      }
    });

    try {
      // Simulate backend REST/GraphQL mutation
      await Future.delayed(const Duration(milliseconds: 400));
    } finally {
      if (mounted) {
        setState(() => _pendingLikes.remove(activity.id));
      }
    }
  }

  @override
  void dispose() {
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
                  _currentUser!.name[0],
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
                ? _buildShimmerSkeleton() // [Point 6]
                : RefreshIndicator(
                    onRefresh: _handleRefresh, // [Point 11]
                    child: _filteredActivities.isEmpty
                        ? _buildAnimatedEmptyState() // [Point 13]
                        : _buildFeedList(), // [Point 17]
                  ),
          ),
        ],
      ),
      // [Point 14] Material 3 Extended FAB for clear, modern visual hierarchy
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

  // [Point 5 & 15] Search input with ValueListenableBuilder and conditional clear button
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, value, child) {
          return TextField(
            controller: _searchController,
            onChanged: (text) => _searchQuery.value = text,
            decoration: InputDecoration(
              hintText: 'Search feed...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: value.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
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

  // [Point 17] Staggered entry animations using flutter_animate
  Widget _buildFeedList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredActivities.length,
      physics: const AlwaysScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final activity = _filteredActivities[index];
        return _ActivityCard(
          activity: activity,
          onLike: () => _handleLike(activity),
        )
        .animate()
        .fadeIn(duration: 300.ms, delay: (50 * index).ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutQuad);
      },
    );
  }

  // [Point 6] Skeletonizer wraps realistic layout for shimmer effects
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

  // [Point 13] Animated, lively empty state replacing static icons
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
}

// ==========================================
// MATERIAL 3 ACTIVITY CARD COMPONENT
// ==========================================

class _ActivityCard extends StatelessWidget {
  final Activity activity;
  final VoidCallback onLike;

  const _ActivityCard({
    required this.activity,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // [Point 18] Material 3 Card with surfaceTint and 0 elevation
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerLow,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // [Point 8 & 16] Hero tag + CachedNetworkImage with memory & disk cache
                Hero(
                  tag: activity.heroTag,
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: activity.avatarUrl ?? '',
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
                // [Point 7] TweenAnimationBuilder creates Instagram-style heart burst
                TweenAnimationBuilder<double>(
                  key: ValueKey(activity.isLiked),
                  tween: Tween(begin: 1.0, end: activity.isLiked ? 1.3 : 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: IconButton(
                        icon: Icon(
                          activity.isLiked ? Icons.favorite : Icons.favorite_border,
                          color: activity.isLiked
                              ? Colors.redAccent
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: onLike,
                      ),
                    );
                  },
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
