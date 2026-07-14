// screens/user_profile_screen.dart
//
// Read-only profile view for *other* users, reached by tapping anyone's
// avatar anywhere in the app (see widgets/user_avatar.dart /
// utils/navigation.dart openUserProfile()). The current user's own avatar
// still opens the full, editable ProfileScreen — this screen is only ever
// pushed for someone else's id.
import 'package:flutter/material.dart' hide Badge;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/timeline_post_model.dart';
import '../models/user.dart';
import '../repositories/group_chat_repository.dart';
import '../repositories/prayer_repository.dart';
import '../repositories/testimony_repository.dart';
import '../repositories/timeline_post_repository.dart';
import '../repositories/user_repository.dart';
import '../widgets/user_avatar.dart';

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

    // Fetched independently — if one endpoint fails (e.g. groups aren't
    // shared with this viewer) the rest of the profile should still render.
    final posts = await _postsRepo
        .fetchUserPosts(widget.userId)
        .catchError((_) => <TimelinePost>[]);
    final prayersCount = await _prayerRepo
        .countUserPrayers(widget.userId)
        .catchError((_) => 0);
    final testimoniesCount = await _testimonyRepo
        .countUserTestimonies(widget.userId)
        .catchError((_) => 0);
    final groupsCount = await _groupRepo
        .getGroups()
        .then((g) => g.length)
        .catchError((_) => 0);

    return _UserProfileData(
      user: user,
      posts: posts,
      prayersCount: prayersCount,
      testimoniesCount: testimoniesCount,
      groupsCount: groupsCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<_UserProfileData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                "Couldn't load this profile.\n${snapshot.error ?? ''}",
                textAlign: TextAlign.center,
              ),
            );
          }

          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: UserAvatar(
                    profilePicture: data.user.profilePicture,
                    username: data.user.username,
                    size: 96,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    data.user.username,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (data.user.createdAt != null)
                  Center(
                    child: Text(
                      'Joined ${DateFormat.yMMMM().format(data.user.createdAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Stat(label: 'Prayers', count: data.prayersCount),
                    _Stat(label: 'Testimonies', count: data.testimoniesCount),
                    _Stat(label: 'Groups', count: data.groupsCount),
                  ],
                ),
                const Divider(height: 32),
                if (data.posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No posts yet.')),
                  )
                else
                  ...data.posts.map((post) => _PostCard(post: post)),
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

class _Stat extends StatelessWidget {
  final String label;
  final int count;

  const _Stat({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  final TimelinePost post;

  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post.content),
            if (post.imageUrl != null && !post.isVideo) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  post.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              DateFormat.yMMMd().add_jm().format(post.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
