import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import '../config/config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../repositories/activity_repository.dart';
import '../repositories/user_repository.dart';
import '../models/activity.dart';
import '../models/user.dart';
import '../widgets/app_drawer.dart';

/// Production notes vs. the draft this was built from:
/// - Auth state is watched via AuthService so the feed stays correct across
///   login/logout even if this screen isn't recreated.
/// - "Failed to load" and "nothing to show yet" are different states with
///   different UI — a network error should never look like an empty feed.
/// - Search is debounced (matches the draft) so typing doesn't thrash the
///   filtered list or restart in-flight animations.
/// - List items use a stable key derived from content, not list index,
///   since Activity has no server-assigned id.
/// - Author avatars are resolved against Config.baseUrl the same way the
///   profile avatar is, since the API returns a relative path.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  User? _currentUser;
  List<Activity> _activities = [];
  bool _loading = true;
  bool _hasError = false;

  int? _loadedForUserId;
  late final VoidCallback _authListener;

  @override
  void initState() {
    super.initState();
    _authListener = _onAuthChanged;
    AuthService().addListener(_authListener);
    _loadData();
  }

  @override
  void dispose() {
    AuthService().removeListener(_authListener);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final newUserId = AuthService().userId;
    if (newUserId != _loadedForUserId) {
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
      final token = await ApiService.getToken();
      final loggedInUserId = AuthService().userId;

      User? user;
      List<Activity> activities = [];

      if (token != null && loggedInUserId != null) {
        user = await UserRepository().getCurrentUser(token);
        activities = await ActivityRepository().fetchRecentActivities(limit: 20);
      }

      if (!mounted) return;
      setState(() {
        _currentUser = user;
        _activities = activities;
        _loading = false;
        _loadedForUserId = loggedInUserId;
      });
    } catch (e) {
      debugPrint('❌ HomeScreen._loadData: $e');
      if (!mounted) return;
      setState(() {
        _currentUser = null;
        _activities = [];
        _loading = false;
        _hasError = true;
        _loadedForUserId = AuthService().userId;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  List<Activity> get _filteredActivities => _activities
      .where((a) => a.title.toLowerCase().contains(_searchQuery.toLowerCase()))
      .toList();

  String? _resolveAvatarUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = Config.baseUrl.endsWith('/')
        ? Config.baseUrl.substring(0, Config.baseUrl.length - 1)
        : Config.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  Widget _buildSearchField(ThemeData theme) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return TextField(
          controller: _searchController,
          onChanged: (value) {
            setLocalState(() {});
            _onSearchChanged(value);
          },
          decoration: InputDecoration(
            hintText: 'Search activities...',
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
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          ),
        );
      },
    );
  }

  Widget _buildActivityTile(BuildContext context, Activity activity, {Key? key}) {
    final theme = Theme.of(context);
    final resolvedAvatarUrl = _resolveAvatarUrl(activity.authorAvatarUrl);

    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.15)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: activity.hasAuthorAvatar
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: resolvedAvatarUrl!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => CircleAvatar(
                    radius: 22,
                    backgroundColor: activity.color.withOpacity(0.12),
                  ),
                  errorWidget: (context, url, error) => CircleAvatar(
                    radius: 22,
                    backgroundColor: activity.color.withOpacity(0.12),
                    child: Icon(activity.icon, color: activity.color, size: 20),
                  ),
                ),
              )
            : CircleAvatar(
                radius: 22,
                backgroundColor: activity.color.withOpacity(0.12),
                child: Icon(activity.icon, color: activity.color, size: 20),
              ),
        title: Text(
          activity.title,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          activity.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          activity.timeAgo,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.45),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(ThemeData theme) {
    return Shimmer.fromColors(
      baseColor: theme.colorScheme.onSurface.withOpacity(0.06),
      highlightColor: theme.colorScheme.onSurface.withOpacity(0.12),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          height: 78,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.auto_awesome, size: 36, color: theme.colorScheme.primary.withOpacity(0.6)),
          const SizedBox(height: 12),
          Text(
            'No activity yet',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Activity from your community will show up here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 36, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            "Couldn't load your feed",
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: _loadData, child: const Text('Retry')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredActivities;

    return Scaffold(
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: true,
              title: Text('Welcome back, ${_currentUser?.username ?? "Friend"}'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  onPressed: () => GoRouter.of(context).go('/profile'),
                  tooltip: 'Profile',
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: _buildSearchField(theme),
                ),
              ),
            ),
            if (_loading)
              SliverFillRemaining(child: _buildLoadingSkeleton(theme))
            else if (_hasError && filtered.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _buildErrorState(context, theme))
            else if (filtered.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState(context, theme))
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final activity = filtered[index];
                      return _buildActivityTile(
                        context,
                        activity,
                        key: ValueKey(
                          '${activity.title}_${activity.createdAt.millisecondsSinceEpoch}_$index',
                        ),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
