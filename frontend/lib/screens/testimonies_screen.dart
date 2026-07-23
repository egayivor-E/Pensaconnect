// screens/testimonies_screen.dart
// ignore_for_file: deprecated_member_use

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/testimony_model.dart';
import '../repositories/testimony_repository.dart';
import '../utils/profile_navigation.dart';
import 'add_testimony_screen.dart';
import 'testimony_detail_screen.dart';

class TestimoniesScreen extends StatefulWidget {
  const TestimoniesScreen({super.key});

  @override
  State<TestimoniesScreen> createState() => _TestimoniesScreenState();
}

class _TestimoniesScreenState extends State<TestimoniesScreen> {
  final _repo = TestimonyRepository();
  late Future<List<Testimony>> _futureTestimonies;

  @override
  void initState() {
    super.initState();
    _futureTestimonies = _repo.fetchTestimonies();
  }

  Future<void> _refresh({bool forceRefresh = true}) async {
    setState(() {
      _futureTestimonies = _repo.fetchTestimonies(forceRefresh: forceRefresh);
    });
    await _futureTestimonies;
  }

  Future<void> _openAddTestimony() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTestimonyScreen()),
    );
    // The add screen posts directly via the repository and just pops —
    // it doesn't hand back a Testimony — so refresh from the server
    // (forcing past the 5-minute cache) to pick up the new entry.
    await _refresh(forceRefresh: true);
  }

  void _openDetail(Testimony t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TestimonyDetailScreen(id: int.parse(t.id)),
      ),
    );
  }

  Future<void> _toggleLike(Testimony t) async {
    try {
      await _repo.toggleLike(int.parse(t.id));
      setState(() {
        // Cache was updated optimistically inside the repository;
        // just re-pull the (now-fresh) cached list to reflect it.
        _futureTestimonies = _repo.fetchTestimonies();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to like: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Testimonies & Stories')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Testimony>>(
          future: _futureTestimonies,
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
                        Text('Failed to load testimonies: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _refresh,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            final testimonies = snapshot.data ?? [];

            if (testimonies.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurface.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No testimonies yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Be the first to share what God has done in your life.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: testimonies.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Recent Testimonies',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
                final t = testimonies[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _TestimonyCard(
                    testimony: t,
                    onTap: () => _openDetail(t),
                    onLike: () => _toggleLike(t),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTestimony,
        icon: const Icon(Icons.add),
        label: const Text('Share'),
      ),
    );
  }
}

class _TestimonyCard extends StatelessWidget {
  final Testimony testimony;
  final VoidCallback onTap;
  final VoidCallback onLike;
  const _TestimonyCard({
    required this.testimony,
    required this.onTap,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => openUserProfile(
                      context,
                      int.tryParse(testimony.authorId),
                      knownUsername: testimony.authorName,
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.primary.withOpacity(
                        0.12,
                      ),
                      child: Icon(
                        Icons.person,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          testimony.authorName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          timeago.format(testimony.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (testimony.imageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 10,
                child: CachedNetworkImage(
                  imageUrl: testimony.imageUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                  placeholder: (_, __) =>
                      Container(color: Colors.grey.shade200),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    testimony.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    testimony.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _ActionChip(
                        icon: testimony.likedByMe
                            ? Icons.favorite
                            : Icons.favorite_border,
                        iconColor: testimony.likedByMe
                            ? Colors.redAccent
                            : null,
                        label: '${testimony.likesCount}',
                        onTap: onLike,
                      ),
                      const SizedBox(width: 8),
                      _ActionChip(
                        icon: Icons.mode_comment_outlined,
                        label: '${testimony.commentsCount}',
                        onTap: onTap,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.share_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: iconColor ?? theme.colorScheme.onSurface.withOpacity(0.65),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
