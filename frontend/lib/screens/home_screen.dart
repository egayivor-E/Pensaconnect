import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart'
    show FontAwesome;
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/config.dart';
import '../widgets/app_drawer.dart';
import '../widgets/feature_card.dart';
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
  User? _currentUser; // ✅ Store full user object instead of just name
  List<Activity> _activities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      User? user;
      if (token != null) {
        user = await UserRepository().getCurrentUser(token);
      }

      final activities = await ActivityRepository().fetchRecentActivities(
        limit: 20,
      );

      if (!mounted) return;
      setState(() {
        _currentUser = user; // ✅ Store full user object
        _activities = activities;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error in _loadData: $e");
      if (!mounted) return;
      setState(() {
        _currentUser = null;
        _activities = [];
        _loading = false;
      });
    }
  }

  int getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4; // Large desktop
    if (width > 800) return 3; // Desktop/tablet
    if (width > 600) return 2; // Tablet
    return 2; // Mobile (2 columns)
  }

  double getChildAspectRatio(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 800) return 1.2; // Wider cards on larger screens
    return 0.9; // Taller cards on mobile
  }

  @override
  void dispose() {
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
              _currentUser!.getProfilePictureUrl(
                Config
                    .baseUrl, // ← Use Config.baseUrl instead of ApiService.baseUrl
              ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isLargeScreen = MediaQuery.of(context).size.width >= 800;
    final bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final crossAxisCount = getCrossAxisCount(context);
    final childAspectRatio = getChildAspectRatio(context);

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

          // ✅ PROFILE AVATAR - Now uses actual user data
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
                    padding: const EdgeInsets.all(16),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Welcome back, ${_currentUser?.username ?? "Friend"}!", // ✅ Use actual user data
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "What would you like to do today?",
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                        // Responsive Grid with proper column counts
                        SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: childAspectRatio,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final feature = filteredFeatures[index];
                            try {
                              return FeatureCard(
                                icon: feature['icon'] as IconData,
                                title: feature['title'] as String,
                                color: feature['color'] as Color,
                                description: feature['description'] as String,
                                onPressed: () => GoRouter.of(
                                  context,
                                ).push(feature['route'] as String),
                              );
                            } catch (e) {
                              debugPrint('Error rendering FeatureCard: $e');
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.grey[600],
                                      size: 32,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Unable to load',
                                      style: theme.textTheme.bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              );
                            }
                          }, childCount: filteredFeatures.length),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        SliverToBoxAdapter(
                          child: Text(
                            "Recent Activity",
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        if (filteredActivities.isEmpty)
                          const SliverToBoxAdapter(
                            child: Center(child: Text("No recent activity")),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final activity = filteredActivities[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: activity.color.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      activity.icon,
                                      color: activity.color,
                                    ),
                                  ),
                                  title: Text(activity.title),
                                  subtitle: Text(activity.subtitle),
                                  trailing: Text(
                                    activity.timeAgo,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              );
                            }, childCount: filteredActivities.length),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
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
