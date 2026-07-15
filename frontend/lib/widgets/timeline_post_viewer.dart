import 'package:flutter/material.dart';
import '../config/config.dart';
import '../models/timeline_post_model.dart';
import '../repositories/timeline_post_repository.dart';
import '../repositories/user_repository.dart';

/// Resolves a possibly-relative media path against Config.baseUrl —
/// same convention used across the app for avatars/activity media.
String? resolveTimelineMediaUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final base = Config.baseUrl.endsWith('/')
      ? Config.baseUrl.substring(0, Config.baseUrl.length - 1)
      : Config.baseUrl;
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$base$normalizedPath';
}

/// Full-screen viewer for a single timeline post — image/video, a
/// like heart with live count, and a comments sheet. Self-contained:
/// it owns its own like/comment-count state and talks to
/// TimelinePostRepository directly, so any screen can open it just by
/// handing it a TimelinePost. [onPostUpdated] lets the caller (Profile's
/// grid, Home's feed) sync its own list back in step whenever the
/// like/comment count changes here.
class TimelinePostViewer extends StatefulWidget {
  final TimelinePost post;
  final bool isOwnPost;
  final ValueChanged<TimelinePost>? onPostUpdated;
  final VoidCallback? onDelete;

  const TimelinePostViewer({
    super.key,
    required this.post,
    required this.isOwnPost,
    this.onPostUpdated,
    this.onDelete,
  });

  @override
  State<TimelinePostViewer> createState() => _TimelinePostViewerState();
}

class _TimelinePostViewerState extends State<TimelinePostViewer> {
  final _repo = TimelinePostRepository();
  late TimelinePost _post;
  bool _liking = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  void _update(TimelinePost updated) {
    setState(() => _post = updated);
    widget.onPostUpdated?.call(updated);
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);
    final wasLiked = _post.hasLiked;
    _update(
      _post.copyWith(
        hasLiked: !wasLiked,
        likeCount: _post.likeCount + (wasLiked ? -1 : 1),
      ),
    );
    try {
      final result = await _repo.toggleLike(_post.id);
      if (!mounted) return;
      _update(
        _post.copyWith(
          hasLiked: result['liked'] == true,
          likeCount:
              (result['like_count'] as num?)?.toInt() ??
              _post.likeCount, // was 'likeCount'
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _update(
        _post.copyWith(
          hasLiked: wasLiked,
          likeCount: _post.likeCount + (wasLiked ? 1 : -1),
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to react: $e')));
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _openComments() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => TimelinePostCommentsSheet(
        postId: _post.id,
        onCountChanged: (count) => _update(_post.copyWith(commentCount: count)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final resolvedUrl = resolveTimelineMediaUrl(post.imageUrl);

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (widget.isOwnPost && widget.onDelete != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  if (value == 'delete') widget.onDelete!();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete post'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {},
                child: Center(
                  child: resolvedUrl == null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            post.content,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : post.isVideo
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                post.content,
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : InteractiveViewer(
                          child: Image.network(
                            resolvedUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 56,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _toggleLike,
                      icon: Icon(
                        post.hasLiked ? Icons.favorite : Icons.favorite_border,
                        color: post.hasLiked ? Colors.redAccent : Colors.white,
                      ),
                    ),
                    Text(
                      '${post.likeCount}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: _openComments,
                      icon: const Icon(
                        Icons.mode_comment_outlined,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${post.commentCount}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TimelinePostCommentsSheet extends StatefulWidget {
  final int postId;
  final ValueChanged<int> onCountChanged;
  const TimelinePostCommentsSheet({
    super.key,
    required this.postId,
    required this.onCountChanged,
  });

  @override
  State<TimelinePostCommentsSheet> createState() =>
      _TimelinePostCommentsSheetState();
}

class _TimelinePostCommentsSheetState extends State<TimelinePostCommentsSheet> {
  final _repo = TimelinePostRepository();
  final _controller = TextEditingController();
  late Future<List<TimelineComment>> _future;
  List<TimelineComment> _comments = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<TimelineComment>> _load() async {
    final comments = await _repo.fetchComments(widget.postId);
    _comments = comments;
    return comments;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await _repo.addComment(widget.postId, text);
      setState(() {
        _comments = [..._comments, comment];
        _controller.clear();
      });
      widget.onCountChanged(_comments.length);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to comment: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Comments',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Divider(height: 20),
              Expanded(
                child: FutureBuilder<List<TimelineComment>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Failed to load comments: ${snapshot.error}',
                        ),
                      );
                    }
                    if (_comments.isEmpty) {
                      return const Center(
                        child: Text('No comments yet. Be the first!'),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _comments.length,
                      itemBuilder: (context, i) {
                        final c = _comments[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundImage: NetworkImage(
                              UserRepository.getProfilePictureUrl(
                                c.authorAvatarUrl,
                              ),
                            ),
                          ),
                          title: Text(
                            c.authorName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(c.content),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                  top: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Write a comment...',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: _send,
                          ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
