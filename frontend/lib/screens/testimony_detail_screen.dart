import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/testimony_model.dart';
import '../repositories/testimony_repository.dart';

class TestimonyDetailScreen extends StatefulWidget {
  final int id;
  const TestimonyDetailScreen({super.key, required this.id});

  @override
  State<TestimonyDetailScreen> createState() => _TestimonyDetailScreenState();
}

class _TestimonyDetailScreenState extends State<TestimonyDetailScreen> {
  final _repo = TestimonyRepository();
  late Future<Testimony> _futureTestimony;
  late Future<List<TestimonyComment>> _futureComments;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    // Try cache first for immediate response
    final cachedTestimony = _repo.getTestimonyFromCache(widget.id);
    if (cachedTestimony != null) {
      _futureTestimony = Future.value(cachedTestimony);
    } else {
      _futureTestimony = _repo.fetchTestimony(widget.id);
    }
    _futureComments = _repo.fetchComments(widget.id);
  }

  Future<void> _refresh() async {
    setState(() {
      _loadData();
    });
    await Future.wait([_futureTestimony, _futureComments]);
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;

    try {
      await _repo.addComment(widget.id, {"content": _commentController.text});
      _commentController.clear();

      // Refresh to get updated comments and comment count
      setState(() {
        _loadData();
      });

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment added successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add comment: $e')));
      }
    }
  }

  Future<void> _toggleLike() async {
    try {
      await _repo.toggleLike(widget.id);
      // Update UI immediately since cache was updated
      setState(() {
        _loadData(); // Reload from updated cache
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
      appBar: AppBar(
        title: const Text('Testimony Detail'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Testimony>(
          future: _futureTestimony,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text('Error: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: Text('No testimony found.'));
            }

            final testimony = snapshot.data!;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (testimony.imageUrl != null)
                    Image.network(
                      testimony.imageUrl!,
                      width: double.infinity,
                      height: 250,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 250,
                          width: double.infinity,
                          color: Colors.grey[200],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text('Failed to load image'),
                            ],
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 250,
                          width: double.infinity,
                          color: Colors.grey[200],
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          testimony.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    testimony.authorName,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    testimony.createdAt
                                        .toLocal()
                                        .toString()
                                        .split(' ')
                                        .first,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          testimony.content,
                          style: const TextStyle(fontSize: 16, height: 1.5),
                        ),
                        const SizedBox(height: 32),

                        /// FIXED: Likes + comments row - use testimony data directly
                        Row(
                          children: [
                            // Like button
                            InkWell(
                              onTap: _toggleLike,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      testimony.likedByMe
                                          ? Icons.thumb_up
                                          : Icons.thumb_up_outlined,
                                      size: 20,
                                      color: testimony.likedByMe
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface
                                                .withOpacity(0.6),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${testimony.likesCount}',
                                      style: TextStyle(
                                        color: testimony.likedByMe
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.onSurface
                                                  .withOpacity(0.6),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Comment button
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.comment_outlined,
                                    size: 20,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${testimony.commentsCount}',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const Divider(height: 40),
                        Text(
                          'Comments',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        FutureBuilder<List<TestimonyComment>>(
                          future: _futureComments,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  'Error loading comments: ${snapshot.error}',
                                ),
                              );
                            }
                            final comments = snapshot.data ?? [];
                            if (comments.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  'No comments yet.\nBe the first to comment!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              );
                            }
                            return Column(
                              children: comments.map((c) {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 1,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: theme.colorScheme.primary
                                          .withOpacity(0.1),
                                      child: Icon(
                                        Icons.person,
                                        color: theme.colorScheme.primary,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      c.authorName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          c.content,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          c.createdAt
                                              .toLocal()
                                              .toString()
                                              .split(' ')
                                              .first,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        /// Add comment box
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add a comment',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _commentController,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    hintText: 'Write your comment here...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    contentPadding: const EdgeInsets.all(16),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        Icons.send,
                                        color: theme.colorScheme.primary,
                                      ),
                                      onPressed: _submitComment,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _submitComment,
                                    child: const Text('Post Comment'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
}
