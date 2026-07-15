import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/testimony_model.dart';
import '../repositories/testimony_repository.dart';
import '../utils/profile_navigation.dart';

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

  // ✅ Same identity-color system as forums/testimonies list.
  static const List<Color> _avatarPalette = [
    Color(0xFF7C4DFF),
    Color(0xFF26A69A),
    Color(0xFFFF7043),
    Color(0xFF42A5F5),
    Color(0xFFEC407A),
    Color(0xFF66BB6A),
    Color(0xFF5C6BC0),
    Color(0xFFFFA726),
  ];

  Color _colorForName(String name) {
    if (name.isEmpty) return _avatarPalette.first;
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return _avatarPalette[hash % _avatarPalette.length];
  }

  String _initialsFor(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  bool _showHeartBurst = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
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

      setState(() {
        _loadData();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Your encouragement was shared 💛'),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
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
      setState(() {
        _loadData();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to like: $e')));
      }
    }
  }

  // ✅ Double-tap to like, matching the gesture already added to forums
  // and the testimonies list — consistent muscle memory across the app.
  void _onContentDoubleTap(Testimony testimony) {
    if (!testimony.likedByMe) {
      _toggleLike();
    }
    setState(() => _showHeartBurst = true);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showHeartBurst = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Testimony'),
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
            final authorColor = _colorForName(testimony.authorName);

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (testimony.imageUrl != null)
                    GestureDetector(
                      onDoubleTap: () => _onContentDoubleTap(testimony),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CachedNetworkImage(
                            imageUrl: testimony.imageUrl!,
                            width: double.infinity,
                            height: 250,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) {
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
                            progressIndicatorBuilder: (context, url, progress) {
                              return Container(
                                height: 250,
                                width: double.infinity,
                                color: Colors.grey[200],
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: progress.progress,
                                  ),
                                ),
                              );
                            },
                          ),
                          AnimatedOpacity(
                            opacity: _showHeartBurst ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: AnimatedScale(
                              scale: _showHeartBurst ? 1.0 : 0.5,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.elasticOut,
                              child: const Icon(
                                Icons.favorite,
                                color: Colors.redAccent,
                                size: 90,
                                shadows: [
                                  Shadow(color: Colors.black38, blurRadius: 14),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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
                            GestureDetector(
                              onTap: () => openUserProfile(
                                context,
                                int.tryParse(testimony.authorId),
                              ),
                              child: CircleAvatar(
                                backgroundColor: authorColor,
                                child: Text(
                                  _initialsFor(testimony.authorName),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
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
                                      color: authorColor,
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

                        // ✅ Double-tap the story text itself to like, same
                        // as the image above — the whole content area is
                        // now a "like surface," matching the forum posts.
                        GestureDetector(
                          onDoubleTap: () => _onContentDoubleTap(testimony),
                          behavior: HitTestBehavior.opaque,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                testimony.content,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                              if (testimony.imageUrl == null)
                                AnimatedOpacity(
                                  opacity: _showHeartBurst ? 1 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: AnimatedScale(
                                    scale: _showHeartBurst ? 1.0 : 0.5,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.elasticOut,
                                    child: const Icon(
                                      Icons.favorite,
                                      color: Colors.redAccent,
                                      size: 84,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black26,
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        Row(
                          children: [
                            InkWell(
                              onTap: _toggleLike,
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: testimony.likedByMe
                                      ? theme.colorScheme.primary.withOpacity(
                                          0.12,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    AnimatedScale(
                                      scale: testimony.likedByMe ? 1.15 : 1.0,
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: Icon(
                                        // ✅ Heart reads as "this moved me,"
                                        // more fitting for a testimony than
                                        // a generic thumbs-up.
                                        testimony.likedByMe
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 20,
                                        color: testimony.likedByMe
                                            ? Colors.redAccent
                                            : theme.colorScheme.onSurface
                                                  .withOpacity(0.6),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${testimony.likesCount}',
                                      style: TextStyle(
                                        color: testimony.likedByMe
                                            ? Colors.redAccent
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline,
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
                          // ✅ "Comments" -> "Words of Encouragement" — this
                          // is a testimony, not a forum thread; the label
                          // should match the emotional register of sharing
                          // something meaningful.
                          'Words of Encouragement',
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
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.mode_comment_outlined,
                                      color: Colors.grey[400],
                                      size: 32,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'No encouragement yet.\nBe the first to celebrate this testimony!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Column(
                              children: comments.map((c) {
                                final commentColor = _colorForName(
                                  c.authorName,
                                );
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 0,
                                  color: Colors.grey.withOpacity(0.06),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: GestureDetector(
                                      onTap: () => openUserProfile(
                                        context,
                                        int.tryParse(c.authorId ?? ''),
                                      ),
                                      child: CircleAvatar(
                                        backgroundColor: commentColor,
                                        child: Text(
                                          _initialsFor(c.authorName),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      c.authorName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: commentColor,
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

                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: theme.colorScheme.primary.withOpacity(
                                0.15,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  // ✅ Warmer framing than a generic
                                  // "Add a comment" label.
                                  'Encourage them',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _commentController,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    hintText:
                                        'Share a word of encouragement...',
                                    filled: true,
                                    fillColor: Colors.grey.withOpacity(0.06),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
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
                                  child: FilledButton(
                                    onPressed: _submitComment,
                                    child: const Text('Send Encouragement'),
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
