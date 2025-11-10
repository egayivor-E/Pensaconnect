import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/utils/forum_event_bus.dart';
import 'package:pensaconnect/utils/role_utils.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/forum_model.dart';
import '../repositories/forum_repository.dart';
import 'package:pensaconnect/utils/forum_event_bus.dart' as forum_bus;

class ForumDetailScreen extends StatefulWidget {
  final int threadId;
  final String threadTitle;

  const ForumDetailScreen({
    super.key,
    required this.threadId,
    required this.threadTitle,
  });

  @override
  State<ForumDetailScreen> createState() => _ForumDetailScreenState();
}

class _ForumDetailScreenState extends State<ForumDetailScreen> {
  // Posts list
  List<ForumPost> _posts = [];

  // per-post comments map
  final Map<int, List<ForumComment>> _commentsMap = {};

  // per-post controllers & attachments & flags
  final Map<int, TextEditingController> _commentControllers = {};
  final Map<int, List<PlatformFile>> _commentAttachments = {};
  final Map<int, bool> _isPostingCommentForPost = {};
  final Map<int, bool> _isCommentsVisible = {};
  final Map<int, bool> _isCommentsLoading = {};

  // global loading / error / retry
  bool _isLoadingPosts = true;
  bool _isFetching = false;
  String? _errorMessage;
  int _retryCount = 0;
  final int _maxRetries = 3;

  // polling + events
  Timer? _pollingTimer;
  final int _pollingIntervalMs = kReleaseMode ? 30000 : 15000;
  StreamSubscription? _postSubscription;
  StreamSubscription? _commentSubscription;

  @override
  void initState() {
    super.initState();
    _fetchPosts(silent: false);
    _setupAutoUpdates();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _postSubscription?.cancel();
    _commentSubscription?.cancel();

    // dispose controllers
    for (final c in _commentControllers.values) {
      c.dispose();
    }

    super.dispose();
  }

  void _setupAutoUpdates() {
    // Polling with guard to avoid overlap
    _pollingTimer = Timer.periodic(Duration(milliseconds: _pollingIntervalMs), (
      _,
    ) {
      if (mounted && !_isFetching) _fetchPosts(silent: true);
    });

    // EventBus listeners
    _postSubscription = ForumEventBus().postEvents.listen((event) {
      if (event is forum_bus.PostCreatedEvent &&
          event.threadId == widget.threadId) {
        _onExternalNewPost(event.post);
      }
    });

    _commentSubscription = ForumEventBus().commentEvents.listen((event) {
      if (event is forum_bus.CommentCreatedEvent &&
          event.threadId == widget.threadId) {
        _onExternalNewComment(event.postId, event.comment);
      }
    });
  }

  bool _backoffActive = false;

  // ---------------------------
  // Fetch posts + optionally comments for visible posts
  // ---------------------------
  Future<void> _fetchPosts({bool silent = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    if (!silent) {
      setState(() {
        _isLoadingPosts = true;
        _errorMessage = null;
      });
    }

    try {
      final repo = context.read<ForumRepository>();

      // small backoff if retries
      if (_retryCount > 0) {
        await Future.delayed(Duration(seconds: 1 * _retryCount));
      }

      final posts = await repo
          .getPosts(widget.threadId)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      // update posts if changed
      if (_postsChanged(posts, _posts)) {
        setState(() {
          _posts = posts;
        });

        // Ensure per-post state exists for any newly fetched posts
        for (final post in posts) {
          _ensurePerPostState(post.id);
        }
      }

      // For any visible comments panels, refresh their comments
      final visiblePostIds = _isCommentsVisible.entries
          .where((e) => e.value == true)
          .map((e) => e.key)
          .toList();
      for (final pid in visiblePostIds) {
        await _fetchCommentsForPost(pid, silent: true);
      }

      // success resets retry count
      _retryCount = 0;
      if (mounted && !silent) {
        setState(() {
          _isLoadingPosts = false;
        });
      }
    } on TimeoutException {
      _handleFetchError('Request timed out. Try again.');
    } on SocketException {
      _handleFetchError('No internet connection.');
    } catch (e) {
      _handleFetchError(e.toString());
    } finally {
      _isFetching = false;
    }
  }

  void _handleFetchError(String message) {
    if (_backoffActive) return; // prevent multiple concurrent retry schedules
    _backoffActive = true;

    _retryCount++;
    debugPrint('Fetch error: $message (attempt $_retryCount)');

    if (_retryCount <= _maxRetries) {
      Future.delayed(Duration(seconds: 2 * _retryCount), () async {
        if (!mounted) return;
        _backoffActive = false;
        await _fetchPosts();
      });
    } else {
      _backoffActive = false;
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
          _errorMessage = '$message\nTap to retry.';
        });
      }
    }
  }

  bool _postsChanged(List<ForumPost> a, List<ForumPost> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (_postChanged(a[i], b[i])) return true;
    }
    return false;
  }

  bool _postChanged(ForumPost x, ForumPost y) {
    return x.id != y.id ||
        x.content != y.content ||
        x.likeCount != y.likeCount ||
        x.commentsCount != y.commentsCount ||
        x.likedByMe != y.likedByMe ||
        x.attachments.length != y.attachments.length;
  }

  // ---------------------------
  // Per-post comments functions
  // ---------------------------
  void _ensurePerPostState(int postId) {
    _commentControllers.putIfAbsent(postId, () => TextEditingController());
    _commentAttachments.putIfAbsent(postId, () => <PlatformFile>[]);
    _isPostingCommentForPost.putIfAbsent(postId, () => false);
    _isCommentsVisible.putIfAbsent(postId, () => false);
    _isCommentsLoading.putIfAbsent(postId, () => false);
    _commentsMap.putIfAbsent(postId, () => <ForumComment>[]);
  }

  Future<void> _fetchCommentsForPost(int postId, {bool silent = false}) async {
    // create per-post state if missing
    _ensurePerPostState(postId);

    if (_isCommentsLoading[postId] == true) return;
    _isCommentsLoading[postId] = true;
    if (!silent && mounted) setState(() {});

    try {
      final repo = context.read<ForumRepository>();
      final comments = await repo
          .getComments(postId)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      _commentsMap[postId] = comments;
    } on TimeoutException {
      debugPrint('Timeout fetching comments for $postId');
    } catch (e) {
      debugPrint('Error fetching comments for $postId: $e');
    } finally {
      _isCommentsLoading[postId] = false;
      if (mounted) setState(() {});
    }
  }

  // toggle per-post comments visibility
  Future<void> _toggleCommentsForPost(int postId) async {
    _ensurePerPostState(postId);
    final visible = _isCommentsVisible[postId] ?? false;
    if (visible) {
      setState(() {
        _isCommentsVisible[postId] = false;
      });
    } else {
      setState(() {
        _isCommentsVisible[postId] = true;
      });
      await _fetchCommentsForPost(postId);
    }
  }

  // ---------------------------
  // Posting comment for a post
  // ---------------------------
  Future<void> _pickAttachmentsForPost(int postId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result != null && mounted) {
        _ensurePerPostState(postId);
        setState(() {
          _commentAttachments[postId] = result.files;
        });
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File pick error: $e')));
      }
    }
  }

  Future<void> _postCommentForPost(int postId) async {
    _ensurePerPostState(postId);
    final controller = _commentControllers[postId]!;
    final text = controller.text.trim();
    final attachments = _commentAttachments[postId] ?? [];

    if (text.isEmpty && attachments.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter content or add attachment')),
        );
      }
      return;
    }

    _isPostingCommentForPost[postId] = true;
    setState(() {});

    try {
      final repo = context.read<ForumRepository>();
      await repo.addComment(
        threadId: widget.threadId, // ✅ Added this line
        postId: postId,
        content: text,
        attachments: attachments,
      );

      controller.clear();
      _commentAttachments[postId] = [];

      // refresh comments for this post
      await _fetchCommentsForPost(postId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // update posts list counts (best-effort): re-fetch posts to keep counts accurate
      _fetchPosts(silent: true);
    } catch (e) {
      debugPrint('Error posting comment for $postId: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to post comment')));
      }
    } finally {
      _isPostingCommentForPost[postId] = false;
      if (mounted) setState(() {});
    }
  }

  // ---------------------------
  // Likes
  // ---------------------------
  Future<void> _toggleLikeOnPost(int index) async {
    if (index >= _posts.length) return;
    final post = _posts[index];
    final wasLiked = post.likedByMe;
    final oldCount = post.likeCount;

    // optimistic UI
    setState(() {
      post.likedByMe = !wasLiked;
      post.likeCount += post.likedByMe ? 1 : -1;
    });

    try {
      final repo = context.read<ForumRepository>();
      await repo.toggleLike(post.id);
      // optionally refresh that post from server in a more advanced setup
    } catch (e) {
      debugPrint('Toggle like failed: $e');
      if (mounted) {
        setState(() {
          post.likedByMe = wasLiked;
          post.likeCount = oldCount;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to toggle like')));
      }
    }
  }

  // ---------------------------
  // Event bus handlers
  // ---------------------------
  void _onExternalNewPost(ForumPost post) {
    if (!mounted) return;
    // Only add if thread matches (event already checks) and not duplicate
    if (!_posts.any((p) => p.id == post.id)) {
      setState(() {
        _posts.insert(0, post);
        _ensurePerPostState(post.id);
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('New post by ${post.authorName}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _onExternalNewComment(int postId, ForumComment comment) async {
    if (!mounted) return;
    // If comments are loaded for that post, insert; else refetch when visible
    if (_commentsMap.containsKey(postId) && _commentsMap[postId] != null) {
      setState(() {
        _commentsMap[postId]?.insert(0, comment);
      });
    } else {
      // nothing loaded yet; fetch later when user opens, but also attempt a silent refresh
      await _fetchCommentsForPost(postId, silent: true);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('New comment from ${comment.authorName}'),
        backgroundColor: Colors.green,
      ),
    );

    // update posts counts (best-effort)
    _fetchPosts(silent: true);
  }

  // ---------------------------
  // UI building
  // ---------------------------
  Widget _buildPostCard(ForumPost post, int index) {
    _ensurePerPostState(post.id);

    final comments = _commentsMap[post.id] ?? [];
    final isVisible = _isCommentsVisible[post.id] ?? false;
    final isLoadingComments = _isCommentsLoading[post.id] ?? false;
    final controller = _commentControllers[post.id]!;
    final attachments = _commentAttachments[post.id] ?? [];
    final isPosting = _isPostingCommentForPost[post.id] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: post.authorAvatar != null
                      ? NetworkImage(post.authorAvatar!)
                      : null,
                  child: post.authorAvatar == null
                      ? Text(
                          post.authorName.isNotEmpty
                              ? post.authorName[0].toUpperCase()
                              : '?',
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (post.createdAt != null)
                        Text(
                          _formatDate(post.createdAt!),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                // optional overflow actions could go here
              ],
            ),

            const SizedBox(height: 12),

            // content
            Text(
              post.content,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),

            if (post.attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: post.attachments.map((a) {
                  return GestureDetector(
                    onTap: () {
                      debugPrint('Open attachment ${a.url}');
                      // TODO: open preview route or modal
                    },
                    child: Image.network(
                      a.url,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 90,
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 8),

            // engagement row
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    post.likedByMe ? Icons.favorite : Icons.favorite_border,
                    color: post.likedByMe ? Colors.red : Colors.grey,
                  ),
                  onPressed: () => _toggleLikeOnPost(index),
                ),
                Text('${post.likeCount}'),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _toggleCommentsForPost(post.id),
                  child: Row(
                    children: [
                      const Icon(Icons.comment_outlined, size: 20),
                      const SizedBox(width: 4),
                      Text('${post.commentsCount}'),
                      const SizedBox(width: 8),
                      Icon(
                        isVisible ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // comments panel (animated)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  const Divider(),
                  if (isLoadingComments)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          'No comments yet. Be the first to comment!',
                        ),
                      ),
                    )
                  else
                    Column(
                      children: comments
                          .map((c) => _buildCommentItem(c))
                          .toList(),
                    ),

                  // comment input
                  const SizedBox(height: 8),
                  if (attachments.isNotEmpty)
                    SizedBox(
                      height: 60,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: attachments.map((f) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Stack(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.grey[200],
                                  ),
                                  child: kIsWeb && f.bytes != null
                                      ? Image.memory(
                                          f.bytes!,
                                          fit: BoxFit.cover,
                                        )
                                      : (f.path != null
                                            ? Image.file(
                                                File(f.path!),
                                                fit: BoxFit.cover,
                                              )
                                            : const SizedBox()),
                                ),
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _commentAttachments[post.id]?.remove(f);
                                      });
                                    },
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        onPressed: () => _pickAttachmentsForPost(post.id),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            hintText: 'Write a comment...',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          minLines: 1,
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      isPosting
                          ? const SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.send),
                              color: Theme.of(context).primaryColor,
                              onPressed: () => _postCommentForPost(post.id),
                            ),
                    ],
                  ),
                ],
              ),
              crossFadeState: (_isCommentsVisible[post.id] ?? false)
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentItem(ForumComment comment) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: comment.authorAvatar != null
              ? NetworkImage(comment.authorAvatar!)
              : null,
          child: comment.authorAvatar == null
              ? Text(
                  comment.authorName.isNotEmpty
                      ? comment.authorName[0].toUpperCase()
                      : '?',
                )
              : null,
        ),
        title: Text(
          comment.authorName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(comment.content),
            if (comment.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: comment.attachments.map((a) {
                    return Image.network(
                      a.url,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image),
                      ),
                    );
                  }).toList(),
                ),
              ),
            if (comment.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _formatDate(comment.createdAt!),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildErrorBody() {
    return GestureDetector(
      onTap: () => _fetchPosts(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 20),
              Text(
                'Connection Issue',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Unable to connect to server',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _fetchPosts(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              Text(
                'Attempt ${_retryCount}/$_maxRetries',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------
  // Build
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.threadTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: RoleGuard(
        roles: ['member', 'admin', 'moderator'],
        child: FloatingActionButton.extended(
          onPressed: () async {
            final created = await context.push(
              '/threads/${widget.threadId}/new-post',
              extra: {
                'threadId': widget.threadId,
                'threadTitle': widget.threadTitle, // pass this
              },
            );
            if (created == true) {
              _fetchPosts();
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('New Post'),
        ),
      ),
      body: _isLoadingPosts
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorBody()
          : _posts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 20),
                    const Text('No Posts Yet', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),
                    const Text(
                      'Be the first to start a discussion in this thread!',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchPosts,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _posts.length,
                itemBuilder: (context, i) => _buildPostCard(_posts[i], i),
              ),
            ),
    );
  }
}
