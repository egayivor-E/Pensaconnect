// screens/user_profile_screen.dart
//
// Read-only profile view for *other* users, reached by tapping anyone's
// avatar anywhere in the app (see widgets/user_avatar.dart /
// utils/profile_navigation.dart openUserProfile()). The current user's own
// avatar still opens the full, editable ProfileScreen — this screen is only
// ever pushed for someone else's id.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/timeline_post_model.dart';
import '../models/user.dart';
import '../repositories/group_chat_repository.dart';
import '../repositories/prayer_repository.dart';
import '../repositories/testimony_repository.dart';
import '../repositories/timeline_post_repository.dart';
import '../repositories/user_repository.dart';
import '../theme/app_style.dart';

class UserProfileScreen extends StatefulWidget {
  final int userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _userRepo = UserRepository();
  final _postsRepo = TimelinePostRepository();
  late final PrayerRepository _prayerRepo;
  late final TestimonyRepository _testimonyRepo;
  late final GroupChatRepository _groupRepo;

  late Future<_UserProfileData> _future;
  bool _startingChat = false;

  @override
  void initState() {
    super.initState();
    _prayerRepo = context.read<PrayerRepository>();
    _testimonyRepo = context.read<TestimonyRepository>();
    _groupRepo = context.read<GroupChatRepository>();
    _future = _load();
  }

  Future<_UserProfileData> _load() async {
    // All five calls only need widget.userId, not each other's results, so
    // they run concurrently rather than the user profile blocking the
    // start of the other four (which was still true even after the fix
    // below, when only those four ran in parallel). If one of the
    // non-critical four fails (e.g. groups aren't shared with this
    // viewer), the rest of the profile should still render — but a failed
    // user fetch is fatal to the whole screen, so it isn't given a
    // catchError and is checked for null explicitly below instead.
    final results = await Future.wait([
      _userRepo.fetchUserProfile(widget.userId),
      _postsRepo
          .fetchUserPosts(widget.userId)
          .then<Object?>((p) => p)
          .catchError((_) => <TimelinePost>[]),
      _prayerRepo
          .countUserPrayers(widget.userId)
          .then<Object?>((c) => c)
          .catchError((_) => 0),
      _testimonyRepo
          .countUserTestimonies(widget.userId)
          .then<Object?>((c) => c)
          .catchError((_) => 0),
      _groupRepo
          .getGroups()
          .then<Object?>((g) => g.length)
          .catchError((_) => 0),
    ]);

    final user = results[0] as User?;
    if (user == null) {
      throw Exception('User not found');
    }
    final posts = results[1] as List<TimelinePost>;
    final prayersCount = results[2] as int;
    final testimoniesCount = results[3] as int;
    final groupsCount = results[4] as int;

    return _UserProfileData(
      user: user,
      posts: posts,
      prayersCount: prayersCount,
      testimoniesCount: testimoniesCount,
      groupsCount: groupsCount,
    );
  }

  Future<void> _message(User user) async {
    if (_startingChat) return;
    setState(() => _startingChat = true);
    try {
      final chat = await _groupRepo.getOrCreateDirectChat(user.id);
      if (!mounted) return;
      context.push(
        '/group-chats/detail',
        extra: {'groupId': chat.id, 'groupName': user.getFullName()},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't start a chat with ${user.getFullName()}."),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: FutureBuilder<_UserProfileData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _ProfileSkeleton();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorState(
              message: "${snapshot.error ?? "Couldn't load this profile."}",
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  stretch: true,
                  expandedHeight: 300,
                  backgroundColor: AppColors.inkDusk,
                  iconTheme: const IconThemeData(color: Colors.white),
                  flexibleSpace: FlexibleSpaceBar(
                    stretchModes: const [StretchMode.zoomBackground],
                    background: _ProfileHeader(user: data.user),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 44,
                          child: FilledButton.icon(
                            onPressed: _startingChat
                                ? null
                                : () => _message(data.user),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.emberGold,
                              foregroundColor: AppColors.inkDusk,
                              shape: AppShapes.pill,
                            ),
                            icon: _startingChat
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.inkDusk,
                                    ),
                                  )
                                : const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              _startingChat ? 'Opening chat…' : 'Message',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _StatsCard(
                          prayersCount: data.prayersCount,
                          testimoniesCount: data.testimoniesCount,
                          groupsCount: data.groupsCount,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Icon(
                              Icons.dynamic_feed_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Timeline',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                if (data.posts.isEmpty)
                  const SliverToBoxAdapter(child: _EmptyPosts())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _PostCard(post: data.posts[index]),
                        ),
                        childCount: data.posts.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserProfileData {
  final User user;
  final List<TimelinePost> posts;
  final int prayersCount;
  final int testimoniesCount;
  final int groupsCount;

  _UserProfileData({
    required this.user,
    required this.posts,
    required this.prayersCount,
    required this.testimoniesCount,
    required this.groupsCount,
  });
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.emberGold.withOpacity(0.25),
      child: const Icon(Icons.person, size: 44, color: Colors.white),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final User user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = UserRepository.getProfilePictureUrl(user.profilePicture);
    final hasPicture =
        user.profilePicture != null && user.profilePicture!.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.inkDusk, AppColors.emberGold],
            ),
          ),
        ),
        DecoratedBox(
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
          left: 0,
          right: 0,
          bottom: 12,
          child: Column(
            children: [
              Container(
                width: 104,
                height: 104,
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
                  child: hasPicture
                      ? CachedNetworkImage(
                          imageUrl: avatarUrl,
                          fit: BoxFit.cover,
                          memCacheWidth:
                              (104 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          memCacheHeight:
                              (104 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          errorWidget: (_, __, ___) => const _AvatarFallback(),
                        )
                      : const _AvatarFallback(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user.getFullName(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              if (user.createdAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Joined ${DateFormat.yMMMM().format(user.createdAt!)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final int prayersCount;
  final int testimoniesCount;
  final int groupsCount;

  const _StatsCard({
    required this.prayersCount,
    required this.testimoniesCount,
    required this.groupsCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: AppShapes.archBorder(top: 20, bottom: 20).borderRadius,
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          _Stat(
            label: 'Prayers',
            count: prayersCount,
            icon: Icons.favorite_rounded,
            color: AppColors.roseQuartz,
          ),
          _StatDivider(),
          _Stat(
            label: 'Testimonies',
            count: testimoniesCount,
            icon: Icons.record_voice_over_rounded,
            color: AppColors.verdantSage,
          ),
          _StatDivider(),
          _Stat(
            label: 'Groups',
            count: groupsCount,
            icon: Icons.groups_rounded,
            color: AppColors.emberGold,
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _Stat({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final TimelinePost post;

  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post.content, style: theme.textTheme.bodyMedium),
            if (post.imageUrl != null && !post.isVideo) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: post.imageUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              DateFormat.yMMMd().add_jm().format(post.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.dynamic_feed_rounded,
            size: 40,
            color: theme.colorScheme.onSurface.withOpacity(0.25),
          ),
          const SizedBox(height: 12),
          Text(
            'No posts yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.inkDusk, AppColors.emberGold],
        ),
      ),
      child: const SafeArea(
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                "Couldn't load this profile",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
