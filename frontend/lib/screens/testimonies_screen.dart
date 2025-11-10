import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/testimony_model.dart';
import '../repositories/testimony_repository.dart';

class TestimoniesScreen extends StatefulWidget {
  const TestimoniesScreen({super.key});

  @override
  State<TestimoniesScreen> createState() => _TestimoniesScreenState();
}

class _TestimoniesScreenState extends State<TestimoniesScreen> {
  final _repo = TestimonyRepository();
  late Future<List<Testimony>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchTestimonies();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _repo.fetchTestimonies(forceRefresh: true);
    });
    await _future;
  }

  Future<void> _deleteTestimony(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Testimony?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repo.deleteTestimony(id);
        if (mounted) _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  // FIXED: Like functionality
  Future<void> _toggleLike(Testimony testimony, int index) async {
    try {
      await _repo.toggleLike(int.parse(testimony.id));
      // Force a complete refresh to get updated data from cache
      setState(() {
        _future = _repo.fetchTestimonies();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to like: $e')));
      }
    }
  }

  // FIXED: Navigate to comments with refresh on return
  void _navigateToComments(Testimony testimony) async {
    await context.push('/testimonies/${testimony.id}');
    // Refresh when returning from detail screen to sync any changes
    if (mounted) {
      setState(() {
        _future = _repo.fetchTestimonies();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Testimonies & Stories')),
      body: FutureBuilder<List<Testimony>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('❌ Error fetching testimonies: ${snapshot.error}');
            return const Center(child: Text('Failed to load testimonies.'));
          }

          final testimonies = snapshot.data ?? [];
          if (testimonies.isEmpty) {
            return const Center(child: Text('No testimonies yet.'));
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: testimonies.length,
              itemBuilder: (context, index) {
                final t = testimonies[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await context.push('/testimonies/${t.id}');
                      // Refresh when returning from detail screen
                      if (mounted) {
                        setState(() {
                          _future = _repo.fetchTestimonies();
                        });
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (t.imageUrl != null)
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            child: Image.network(
                              t.imageUrl!,
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 150,
                                  width: double.infinity,
                                  color: Colors.grey[200],
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                    size: 50,
                                  ),
                                );
                              },
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      t.title,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        _deleteTestimony(int.parse(t.id)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t.content.length > 100
                                    ? '${t.content.substring(0, 100)}...'
                                    : t.content,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: theme.colorScheme.primary
                                        .withOpacity(0.1),
                                    child: Icon(
                                      Icons.person,
                                      color: theme.colorScheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t.authorName,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    t.createdAt
                                        .toLocal()
                                        .toString()
                                        .split(" ")
                                        .first,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // FIXED: Interactive like and comment buttons
                              Row(
                                children: [
                                  // Like button
                                  InkWell(
                                    onTap: () => _toggleLike(t, index),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            t.likedByMe
                                                ? Icons.thumb_up
                                                : Icons.thumb_up_outlined,
                                            size: 18,
                                            color: t.likedByMe
                                                ? theme.colorScheme.primary
                                                : Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${t.likesCount}',
                                            style: TextStyle(
                                              color: t.likedByMe
                                                  ? theme.colorScheme.primary
                                                  : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Comment button
                                  InkWell(
                                    onTap: () => _navigateToComments(t),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.comment,
                                            size: 18,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${t.commentsCount}',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Navigate to add screen
          await context.push('/testimonies/add');

          // When we return, just refresh the data
          if (mounted) {
            setState(() {
              _future = _repo.fetchTestimonies(); // Simple refresh
            });
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
