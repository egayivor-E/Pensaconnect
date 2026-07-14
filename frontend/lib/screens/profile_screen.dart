// screens/profile_screen.dart
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart' hide Badge;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/config.dart';
import '../models/badge.dart';
import '../models/profile_view_model.dart';
import '../models/timeline_post_model.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../repositories/timeline_post_repository.dart';
import '../repositories/user_repository.dart';
import '../theme/app_style.dart';
import 'create_timeline_post_screen.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'change_password_screen.dart';
import 'terms_privacy_screen.dart';
import 'help_support_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  final _postsRepo = TimelinePostRepository();

  // Cover photo has no backend field yet, so it stays a local, in-session
  // preview only — same honest limitation as before, just isolated to the
  // one piece of the UI that's actually still a mock.
  File? _coverFile;

  Future<List<TimelinePost>>? _futurePosts;
  int? _postsLoadedForUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<ProfileViewModel>();
      if (vm.user == null && !vm.isLoading) {
        vm.loadProfile();
      }
    });
  }

  void _ensurePostsLoaded(int userId) {
    if (_postsLoadedForUserId == userId) return;
    _postsLoadedForUserId = userId;
    _futurePosts = _postsRepo.fetchUserPosts(userId);
  }

  Future<void> _refreshPosts(int userId) async {
    setState(() => _futurePosts = _postsRepo.fetchUserPosts(userId));
    await _futurePosts;
  }

  // Post media (images/videos) come back from the backend as a relative
  // path — same convention as activity and user avatars elsewhere in the
  // app (see HomeScreen._resolveAvatarUrl). Image.network needs an
  // absolute URL, so without this a relative path silently fails to load
  // and just shows the errorBuilder / nothing.
  String? _resolvePostMediaUrl(String? path) {
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

  Future<void> _openCreatePost(int userId) async {
    final created = await Navigator.push<TimelinePost>(
      context,
      MaterialPageRoute(builder: (context) => const CreateTimelinePostScreen()),
    );
    if (created != null) {
      await _refreshPosts(userId);
    }
  }

  Future<void> _confirmDeletePost(TimelinePost post, int userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post'),
        content: const Text(
          'This will remove the post everywhere, including the community feed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _postsRepo.deletePost(post.id);
        await _refreshPosts(userId);
      } catch (e) {
        _showSnack('Failed to delete post: $e');
      }
    }
  }

  bool _isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 700;

  Future<void> _pickCover() async {
    final source = await _showImageSourceSheet(
      title: 'Update cover photo',
      allowRemove: _coverFile != null,
    );
    if (source == null) return;
    if (source == _PickAction.remove) {
      setState(() => _coverFile = null);
      return;
    }
    final picked = await _picker.pickImage(
      source: source == _PickAction.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() => _coverFile = File(picked.path));
    _showSnack('Cover photo updated');
  }

  Future<_PickAction?> _showImageSourceSheet({
    required String title,
    required bool allowRemove,
  }) {
    return showModalBottomSheet<_PickAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, _PickAction.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, _PickAction.gallery),
              ),
              if (allowRemove)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Remove current photo',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => Navigator.pop(ctx, _PickAction.remove),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openEditProfile(User user) async {
    final updated = await Navigator.push<User>(
      context,
      MaterialPageRoute(builder: (context) => EditProfileScreen(user: user)),
    );
    if (updated != null && mounted) {
      // The edit screen already persisted the change server-side; just
      // reload so the rest of the profile (avatar, name, email) reflects it.
      await context.read<ProfileViewModel>().loadProfile();
      _showSnack('Profile updated');
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text(
          'Are you sure you want to log out of PensaConnect?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileViewModel>();

    if (vm.isLoading && vm.user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (vm.error != null && vm.user == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.red),
                const SizedBox(height: 16),
                Text('Couldn\'t load your profile: ${vm.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      context.read<ProfileViewModel>().loadProfile(),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final user = vm.user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('No profile found.')));
    }

    _ensurePostsLoaded(user.id);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () => Future.wait([
            context.read<ProfileViewModel>().loadProfile(),
            _refreshPosts(user.id),
          ]),
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              _buildHeaderSliver(context, user),
              _buildStatsAndInfoSliver(context, vm, user),
              _buildStickyTabBar(context),
            ],
            body: TabBarView(
              children: [
                _buildPostsGrid(context, user),
                _buildBadgesGrid(context, vm.badges),
                _buildSettings(context, user),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openCreatePost(user.id),
          icon: const Icon(Icons.add),
          label: const Text('New Post'),
        ),
      ),
    );
  }

  Widget _buildHeaderSliver(BuildContext context, User user) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isWide = _isWide(context);
    final avatarSize = isWide ? 132.0 : 104.0;
    final avatarUrl = UserRepository.getProfilePictureUrl(user.profilePicture);

    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: isWide ? 340 : 300,
      backgroundColor: primary,
      iconTheme: const IconThemeData(color: Colors.white),
      // ✅ Back arrow: pops if this screen was pushed (e.g. reached from
      // another user's profile, a notification, etc). If there's nothing
      // to pop — e.g. Profile is a bottom-tab/root route in go_router with
      // no back stack — falls back to navigating home instead of showing
      // a dead/missing button.
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        tooltip: 'Back',
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/');
          }
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          tooltip: 'App Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsScreen()),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: _pickCover,
              child: _coverFile != null
                  ? Image.file(_coverFile!, fit: BoxFit.cover)
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.inkDusk, AppColors.emberGold],
                        ),
                      ),
                    ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.05),
                    Colors.black.withOpacity(0.55),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 96,
              child: _RoundIconButton(
                icon: Icons.camera_alt_outlined,
                onTap: _pickCover,
                tooltip: 'Change cover photo',
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: theme.colorScheme.primaryContainer,
                              child: const Icon(Icons.person, size: 40),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: _RoundIconButton(
                          icon: Icons.edit,
                          size: 32,
                          iconSize: 16,
                          onTap: () => _openEditProfile(user),
                          tooltip: 'Edit profile',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    user.getFullName(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.4)),
                    ),
                    child: Text(
                      user.roles.isNotEmpty ? user.roles.first : 'Member',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildStatsAndInfoSliver(
    BuildContext context,
    ProfileViewModel vm,
    User user,
  ) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isWide = _isWide(context);

    final statEntries = <_StatEntry>[
      _StatEntry(
        'Prayers',
        vm.prayersCount,
        () => context.push('/prayer-wall'),
      ),
      _StatEntry(
        'Testimonies',
        vm.testimoniesCount,
        () => context.push('/testimonies'),
      ),
      _StatEntry('Groups', vm.groupsCount, () => context.push('/group-chats')),
    ];

    return SliverToBoxAdapter(
      child: Transform.translate(
        offset: const Offset(0, -18),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 720 : double.infinity,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: statEntries.map((e) {
                        final isLast = e == statEntries.last;
                        return Row(
                          children: [
                            InkWell(
                              onTap: e.onTap,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${e.value}',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: primary,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      e.label,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!isLast)
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                width: 1,
                                height: 30,
                                color: theme.dividerColor,
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    user.email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
                if (user.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Member since ${DateFormat('MMMM yyyy').format(user.createdAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => _openEditProfile(user),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit Profile'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStickyTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyTabBarDelegate(
        TabBar(
          labelColor: primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
          indicatorColor: primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.grid_on_rounded), text: 'Posts'),
            Tab(icon: Icon(Icons.emoji_events_outlined), text: 'Badges'),
            Tab(icon: Icon(Icons.settings_outlined), text: 'Settings'),
          ],
        ),
        theme.scaffoldBackgroundColor,
      ),
    );
  }

  Widget _buildPostsGrid(BuildContext context, User user) {
    final theme = Theme.of(context);
    return FutureBuilder<List<TimelinePost>>(
      future: _futurePosts,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 56,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text('Failed to load posts: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _refreshPosts(user.id),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              _EmptyState(
                icon: Icons.photo_library_outlined,
                title: 'No posts yet',
                subtitle: 'Tap "New Post" to share a photo, video, or update.',
              ),
            ],
          );
        }

        final width = MediaQuery.sizeOf(context).width;
        final crossAxisCount = width >= 1000 ? 5 : (width >= 700 ? 4 : 3);

        return GridView.builder(
          padding: const EdgeInsets.all(2),
          itemCount: posts.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemBuilder: (context, i) {
            final post = posts[i];
            final isOwnPost = post.userId == user.id;
            final resolvedUrl = _resolvePostMediaUrl(post.imageUrl);
            return GestureDetector(
              onTap: () => _openPostViewer(context, post),
              onLongPress: isOwnPost
                  ? () => _confirmDeletePost(post, user.id)
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (resolvedUrl != null)
                    Image.network(
                      resolvedUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: theme.colorScheme.surfaceVariant,
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: theme.colorScheme.surfaceVariant,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    )
                  else
                    Container(
                      color: theme.colorScheme.surfaceVariant,
                      padding: const EdgeInsets.all(6),
                      alignment: Alignment.center,
                      child: Text(
                        post.content,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (post.isVideo)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 20,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
                      ),
                    ),
                  // ✅ Visible delete affordance for the post owner's own
                  // tiles, in addition to the long-press above — a
                  // long-press-only action was too easy to never discover.
                  if (isOwnPost)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: GestureDetector(
                        onTap: () => _confirmDeletePost(post, user.id),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openPostViewer(BuildContext context, TimelinePost post) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _PostViewer(
          post: post,
          resolvedImageUrl: _resolvePostMediaUrl(post.imageUrl),
        ),
      ),
    );
  }

  Widget _buildBadgesGrid(BuildContext context, List<Badge> badges) {
    final theme = Theme.of(context);
    if (badges.isEmpty) {
      return const _EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No badges yet',
        subtitle:
            'Pray, share a testimony, or join a group to start earning badges.',
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 1000 ? 4 : (width >= 700 ? 3 : 2);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: badges.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.6,
          ),
          itemBuilder: (context, i) {
            final b = badges[i];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: b.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: b.color.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: b.color.withOpacity(0.18),
                    child: Icon(b.icon, color: b.color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettings(BuildContext context, User user) {
    final theme = Theme.of(context);
    final isWide = _isWide(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SettingsGroup(
              title: 'Account',
              children: [
                _SettingsTile(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  subtitle: user.email,
                  onTap: () => _openEditProfile(user),
                ),
                _SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChangePasswordScreen(),
                    ),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications & App Settings',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy & Terms',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TermsAndPrivacyScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SettingsGroup(
              title: 'Support',
              children: [
                _SettingsTile(
                  icon: Icons.help_outline,
                  title: 'Help Center',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HelpAndSupportScreen(),
                    ),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.info_outline,
                  title: 'About PensaConnect',
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'PensaConnect',
                    applicationIcon: const Icon(Icons.people_alt_rounded),
                    children: const [
                      Text(
                        'A home for the Ladies & Gents Wing to pray, share '
                        'testimonies, study together, and stay connected.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout),
                label: const Text('Log Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _StatEntry {
  final String label;
  final int value;
  final VoidCallback onTap;
  _StatEntry(this.label, this.value, this.onTap);
}

enum _PickAction { camera, gallery, remove }

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final button = Material(
      color: primary,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: List.generate(children.length * 2 - 1, (i) {
              if (i.isEven) return children[i ~/ 2];
              return const Divider(height: 1, indent: 56);
            }),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: primary.withOpacity(0.1),
        child: Icon(icon, color: primary, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: theme.colorScheme.onSurface.withOpacity(0.25),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;
  _StickyTabBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _PostViewer extends StatelessWidget {
  final TimelinePost post;
  final String? resolvedImageUrl;
  const _PostViewer({required this.post, required this.resolvedImageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        extendBodyBehindAppBar: true,
        body: Center(
          child: resolvedImageUrl == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    post.content,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                )
              : post.isVideo
              // A full inline video player is a separate dependency
              // decision (video_player/chewie are already used
              // elsewhere in the app for worship); wire the same
              // player in here once you want in-viewer playback.
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 72,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        post.content,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : InteractiveViewer(
                  child: Image.network(resolvedImageUrl!, fit: BoxFit.contain),
                ),
        ),
      ),
    );
  }
}
