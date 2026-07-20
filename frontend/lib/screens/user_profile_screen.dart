// screens/user_profile_screen.dart
//
// Read-only profile view for *other* users, reached by tapping anyone's
// avatar anywhere in the app (see widgets/user_avatar.dart /
// utils/profile_navigation.dart openUserProfile()). The current user's own
// avatar still opens the full, editable ProfileScreen — this screen is only
// ever pushed for someone else's id.
import 'dart:async';

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
import '../widgets/timeline_post_tile.dart';
import '../widgets/timeline_post_viewer.dart';

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

  bool _startingChat = false;

  // ✅ FIX ("timeline doesn't show like on your own profile" / "delays
  // loading" / "like is missing"): posts used to be fetched *inside* the
  // same Future.wait as the prayer/testimony counts, all gated behind one
  // `_detailsLoading` flag that also hid the timeline. So viewing someone
  // else's profile made the timeline (and every like button on it) wait
  // on two count endpoints it has nothing to do with — if either count
  // call was slow, the timeline just sat there not rendering, looking
  // "missing." The own-profile screen never had this problem because
  // `_loadPosts` there runs fully independently of ProfileViewModel's
  // stats loading. `_postsLoading` now gates only the timeline section,
  // separately from `_detailsLoading` (stats/badges), and both start
  // concurrently instead of stats blocking on posts or vice versa.
  List<TimelinePost> _posts = [];
  bool _postsLoading = true;
  final Set<int> _likedPostIds = {};
  final Set<int> _postActionInFlight = {};

  User? _user;
  bool _loading = true;
  bool _detailsLoading = true;
  String? _error;
  int _prayersCount = 0;
  int _testimoniesCount = 0;
  int _groupsCount = 0;
  List<Badge> _badges = [];

  @override
  void initState() {
    super.initState();
    _prayerRepo = context.read<PrayerRepository>();
    _testimonyRepo = context.read<TestimonyRepository>();
    _groupRepo = context.read<GroupChatRepository>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _detailsLoading = true;
      _postsLoading = true;
      _error = null;
    });

    // Posts don't depend on `_user` or on the stats calls at all — they
    // only need widget.userId, which is already known — so kick them off
    // immediately and let them render the moment they land, completely
    // independently of everything below.
    unawaited(_loadPosts());

    try {
      final user = await _userRepo.fetchUserProfile(widget.userId);
      if (user == null) {
        throw Exception('User not found');
      }
      if (!mounted) return;
      // Header can render now — nothing below depends on it finishing.
      setState(() {
        _user = user;
        _loading = false;
      });

      // ✅ FIX ("why is it slow"), part 1: these two calls are
      // independent of each other (neither needs the other's result), but
      // were previously `await`-ed one after another, so the screen
      // waited for the *sum* of both round-trips instead of just the
      // slower one. Future.wait runs them concurrently — each
      // .catchError still applies per-call, so one endpoint failing
      // still can't block the other from rendering.
      final results = await Future.wait([
        _prayerRepo.countUserPrayers(widget.userId).catchError((_) => 0),
        _testimonyRepo.countUserTestimonies(widget.userId).catchError((_) => 0),
      ]);

      final prayersCount = results[0];
      final testimoniesCount = results[1];

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

      if (!mounted) return;
      setState(() {
        _prayersCount = prayersCount;
        _testimoniesCount = testimoniesCount;
        _groupsCount = groupsCount;
        _badges = badges;
        _detailsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _detailsLoading = false;
      });
    }
  }

  Future<void> _loadPosts() async {
    try {
      final posts = await _postsRepo.fetchUserPosts(widget.userId);
      if (!mounted) return;
      setState(() {
        // Rebuilt fresh from this load's hasLiked flags, same as the
        // own-profile screen — otherwise a like made just before a
        // pull-to-refresh could get stomped by the server's fresher state.
        _posts = posts;
        _likedPostIds
          ..clear()
          ..addAll(posts.where((p) => p.hasLiked).map((p) => p.id));
        _postsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _posts = [];
        _postsLoading = false;
      });
    }
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

  // Optimistic like/unlike, mirroring _toggleLike on the own-profile
  // screen — flips the UI immediately and rolls back only if the request
  // actually fails, instead of waiting a full round-trip to react.
  Future<void> _toggleLike(TimelinePost post) async {
    if (_postActionInFlight.contains(post.id)) return;
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index == -1) return;

    final wasLiked = _likedPostIds.contains(post.id);
    setState(() {
      _postActionInFlight.add(post.id);
      final current = _posts[index];
      final newCount = (current.likeCount + (wasLiked ? -1 : 1)).clamp(
        0,
        1 << 31,
      );
      _posts[index] = current.copyWith(
        likeCount: newCount,
        hasLiked: !wasLiked,
      );
      wasLiked ? _likedPostIds.remove(post.id) : _likedPostIds.add(post.id);
    });

    try {
      await _postsRepo.toggleLike(post.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final current = _posts[index];
        final revertedCount = (current.likeCount + (wasLiked ? 1 : -1)).clamp(
          0,
          1 << 31,
        );
        _posts[index] = current.copyWith(
          likeCount: revertedCount,
          hasLiked: wasLiked,
        );
        wasLiked ? _likedPostIds.add(post.id) : _likedPostIds.remove(post.id);
      });
    } finally {
      if (mounted) setState(() => _postActionInFlight.remove(post.id));
    }
  }

  // Shared full-screen viewer (image/video + like + comments) — same
  // widget the own-profile screen uses. isOwnPost is always false here:
  // this screen is only ever pushed for *someone else's* profile (see the
  // file header note), so there's never a delete option to offer.
  void _openPostViewer(TimelinePost post) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => TimelinePostViewer(
          post: post,
          isOwnPost: false,
          onPostUpdated: (updated) {
            if (!mounted) return;
            final index = _posts.indexWhere((p) => p.id == updated.id);
            if (index == -1) return;
            setState(() {
              _posts[index] = updated;
              updated.hasLiked
                  ? _likedPostIds.add(updated.id)
                  : _likedPostIds.remove(updated.id);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: _ProfileSkeleton());
    }
    if (_error != null || _user == null) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: _ErrorState(
          message: _error ?? "Couldn't load this profile.",
          onRetry: _load,
        ),
      );
    }

    final user = _user!;
    final postsWidth = MediaQuery.sizeOf(context).width;
    final postsCrossAxisCount = postsWidth >= 1000
        ? 5
        : (postsWidth >= 700 ? 4 : 3);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _load,
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
                background: _ProfileHeader(user: user),
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
                        onPressed: _startingChat ? null : () => _message(user),
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Stats/badges/timeline stream in a beat after the
                    // header — show a lightweight inline spinner in their
                    // place instead of blocking the header behind them.
                    if (_detailsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else ...[
                      _StatsCard(
                        prayersCount: _prayersCount,
                        testimoniesCount: _testimoniesCount,
                        groupsCount: _groupsCount,
                      ),
                      const SizedBox(height: 24),
                      _BadgesSection(badges: _badges),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Icon(
                          Icons.dynamic_feed_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
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
            if (_postsLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (_posts.isEmpty)
              const SliverToBoxAdapter(child: _EmptyPosts())
            else
              // Same square thumbnail grid as the "Posts" tab on the
              // owner's own profile (profile_screen.dart), so a post
              // looks identical whether you're viewing your own profile
              // or someone else's.
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: postsCrossAxisCount,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final post = _posts[index];
                    return TimelinePostTile(
                      post: post,
                      isLiked: _likedPostIds.contains(post.id),
                      isInFlight: _postActionInFlight.contains(post.id),
                      crossAxisCount: postsCrossAxisCount,
                      onTap: () => _openPostViewer(post),
                      onLike: () => _toggleLike(post),
                    );
                  }, childCount: _posts.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
