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

import '../models/badge.dart';
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
    final user = await _userRepo.fetchUserProfile(widget.userId);
    if (user == null) {
      throw Exception('User not found');
    }

    // ✅ FIX: these three calls are independent of each other (none needs
    // another's result), but were previously `await`-ed one after another,
    // so the screen waited for the *sum* of all three round-trips instead
    // of just the slowest one. Future.wait runs them concurrently — each
    // .catchError still applies per-call, so one endpoint failing (e.g.
    // groups not shared with this viewer) still can't block the others
    // from rendering.
    final results = await Future.wait([
      _postsRepo
          .fetchUserPosts(widget.userId)
          .catchError((_) => <TimelinePost>[]),
      _prayerRepo.countUserPrayers(widget.userId).catchError((_) => 0),
      _testimonyRepo.countUserTestimonies(widget.userId).catchError((_) => 0),
    ]);

    final posts = results[0] as List<TimelinePost>;
    final prayersCount = results[1] as int;
    final testimoniesCount = results[2] as int;

    // ✅ FIX: this used to call _groupRepo.getGroups(), but that hits
    // GET /group-chats/, which the backend scopes to the *logged-in*
    // viewer's own memberships (see backend/api/v1/group_chats.py —
    // it reads get_jwt_identity(), not widget.userId). So every profile
    // you viewed showed *your own* group count instead of theirs.
    // user.groupChatsCount comes from the same GET /users/:id call that
    // fetched `user` above, and the backend computes it from that
    // specific user's own group_memberships (see User.to_dict() in
    // backend/models.py), so it's actually scoped correctly.
    final groupsCount = user.groupChatsCount;

    // Same rules as the own-profile screen (models/profile_view_model.dart),
    // applied to *this* user's own counts/join-date — not the viewer's —
    // so badges shown here actually belong to the person being viewed.
    final badges = computeBadges(
      prayersCount: prayersCount,
      testimoniesCount: testimoniesCount,
      groupsCount: groupsCount,
      createdAt: user.createdAt,
    );

    return _UserProfileData(
      user: user,
      posts: posts,
      prayersCount: prayersCount,
      testimoniesCount: testimoniesCount,
      groupsCount: groupsCount,
      badges: badges,
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
                        _BadgesSection(badges: data.badges),
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
  final List<Badge> badges;

  _UserProfileData({
    required this.user,
    required this.posts,
    required this.prayersCount,
    required this.testimoniesCount,
    required this.groupsCount,
    required this.badges,
  });
}

class _ProfileHeader extends StatelessWidget {
  final User user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = UserRepository.getProfilePictureUrl(user.profilePicture);

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
                  child: CachedNetworkImage(
                    imageUrl: avatarUrl,
                    fit: BoxFit.cover,
                    memCacheWidth:
                        (104 * MediaQuery.devicePixelRatioOf(context)).round(),
                    memCacheHeight:
                        (104 * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.emberGold.withOpacity(0.25),
                      child: const Icon(
                        Icons.person,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
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

class _BadgesSection extends StatelessWidget {
  final List<Badge> badges;

  const _BadgesSection({required this.badges});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (badges.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: AppShapes.archBorder(top: 20, bottom: 20).borderRadius,
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.12),
          ),
        ),
        child: Center(
          child: Text(
            'No badges yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: badges
          .map(
            (b) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: b.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: b.color.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: b.color.withOpacity(0.18),
                    child: Icon(b.icon, color: b.color, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    b.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
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
