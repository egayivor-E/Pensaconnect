import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/providers/auth_provider.dart';
import 'package:pensaconnect/repositories/user_repository.dart';
import 'package:pensaconnect/utils/profile_navigation.dart';
import 'package:pensaconnect/utils/forum_event_bus.dart';
import 'package:pensaconnect/utils/role_utils.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/forum_model.dart';
import '../repositories/forum_repository.dart';
import 'package:pensaconnect/utils/forum_event_bus.dart' as forum_bus;
import '../theme/app_style.dart';

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

  // ✅ NEW: transient double-tap heart-burst state, keyed by post id
  final Map<int, bool> _showHeartBurst = {};

  // global loading / error / retry
  bool _isLoadingPosts = true;
  bool _isFetching = false;
  String? _errorMessage;
  int _retryCount = 0;
  // A Render free-tier cold start can take up to ~60s. 3 retries at a
  // 10s timeout each wasn't a wide enough window to reliably survive
  // one, so a genuine cold start looked identical to a real failure.
  final int _maxRetries = 5;

  // polling + events
  Timer? _pollingTimer;
  final int _pollingIntervalMs = kReleaseMode ? 30000 : 15000;
  StreamSubscription? _postSubscription;
  StreamSubscription? _commentSubscription;

  // ✅ NEW: scroll control + "new post" banner, so a live post doesn't just
  // silently insert or flash a forgettable SnackBar — it becomes a real,
  // tappable "someone just posted" moment, the same pattern Twitter/X uses
  // for new tweets. This is the single biggest engagement lever for a
  // real-time forum: it makes the app feel alive *while you're in it*.
  final ScrollController _scrollController = ScrollController();
  bool _showNewPostBanner = false;
  ForumPost? _latestNewPost;
  Timer? _bannerTimer;

  // ✅ NEW: a small fixed palette (harmonizes with the app's purple theme)
  // used to give every author a consistent, distinct avatar color derived
  // from their name. This directly fixes "every avatar looks identical" —
  // no backend change needed, and it's honest (not fabricated data, just
  // a deterministic color pick).
  // ✅ A brand-derived palette instead of a generic rainbow — every tone
  // here is pulled from or blended with the app's own "golden hour
  // fellowship" tokens (ember gold, verdant sage, rose quartz, ink dusk),
  // so avatars feel like they belong to this app rather than any app.
  static const List<Color> _avatarPalette = [
    AppColors.emberGold,
    AppColors.verdantSage,
    AppColors.roseQuartz,
    Color(0xFF8A6FB8), // dusk violet — between inkDusk and roseQuartz
    Color(0xFFC77B3F), // toasted amber — deeper ember
    Color(0xFF3E8E86), // teal sage — cooler cousin of verdantSage
    AppColors.inkDusk,
    Color(0xFFD1A24A), // candlelight — lighter ember
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

  // ✅ Mirrors the backend's can_manage() check (forums.py): the author
  // of the content, or a moderator/admin, can manage it. Keeping this
  // check on the client just controls whether the delete affordance is
  // *shown* — the backend still enforces it independently on every
  // DELETE request, so this is UX, not the security boundary.
  bool _canManage(int authorId) {
    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUser;
    if (currentUser == null) return false;
    if (currentUser.id == authorId) return true;
    return auth.hasAnyRole(const ['admin', 'moderator']);
  }

  bool _isStaff() {
    final auth = context.read<AuthProvider>();
    return auth.hasAnyRole(const ['admin', 'moderator']);
  }

  Future<void> _reportPost(ForumPost post) async {
    try {
      final message = await context.read<ForumRepository>().reportPost(post.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      debugPrint('Report post failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not submit report')));
    }
  }

  Future<void> _reportComment(ForumComment comment) async {
    try {
      final message = await context.read<ForumRepository>().reportComment(
        comment.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      debugPrint('Report comment failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not submit report')));
    }
  }

  // Staff-only: ask the assistant to draft + post a labeled reply on this
  // post. It never posts on its own — this is the only path that creates
  // assistant content, and it always requires an explicit moderator tap.
  Future<void> _askAssistantToReply(ForumPost post) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asking the assistant to reply…')),
    );
    try {
      final comment = await context.read<ForumRepository>().requestAiReply(
        post.id,
      );
      if (!mounted) return;
      setState(() {
        _commentsMap.putIfAbsent(post.id, () => []).add(comment);
        _isCommentsVisible[post.id] = true;
        final idx = _posts.indexWhere((p) => p.id == post.id);
        if (idx != -1) _posts[idx].commentsCount += 1;
      });
    } catch (e) {
      debugPrint('AI reply failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Assistant reply failed: $e')));
    }
  }

  // Staff-only: collects a short instruction (e.g. "Write a reflection
  // prompt about patience") then has the assistant draft + post it as a
  // new, clearly-labeled post inside this existing thread. It can never
  // create a thread on its own — a human already had to open this one.
  Future<void> _promptAssistantThreadPost() async {
    final controller = TextEditingController();
    final instruction = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ask the assistant'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'e.g. Write a short reflection prompt about patience',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    if (instruction == null || instruction.isEmpty || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asking the assistant to write this…')),
    );
    try {
      final post = await context.read<ForumRepository>().requestAiThreadPost(
        widget.threadId,
        instruction: instruction,
      );
      if (!mounted) return;
      setState(() => _posts.insert(0, post));
    } catch (e) {
      debugPrint('AI thread post failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Assistant could not post: $e')));
    }
  }

  Future<bool> _confirmDelete(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete $what?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deletePost(ForumPost post) async {
    if (!await _confirmDelete('post')) return;
    try {
      await context.read<ForumRepository>().deletePost(post.id);
      if (!mounted) return;
      setState(() {
        _posts.removeWhere((p) => p.id == post.id);
        _commentsMap.remove(post.id);
        _commentControllers.remove(post.id)?.dispose();
        _commentAttachments.remove(post.id);
        _isPostingCommentForPost.remove(post.id);
        _isCommentsVisible.remove(post.id);
        _isCommentsLoading.remove(post.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post deleted')));
    } catch (e) {
      debugPrint('Delete post failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete post')));
    }
  }

  Future<void> _deleteComment(ForumComment comment) async {
    if (!await _confirmDelete('comment')) return;
    try {
      await context.read<ForumRepository>().deleteComment(
        comment.postId,
        comment.id,
      );
      if (!mounted) return;
      setState(() {
        _commentsMap[comment.postId]?.removeWhere((c) => c.id == comment.id);
        final idx = _posts.indexWhere((p) => p.id == comment.postId);
        if (idx != -1) {
          _posts[idx].commentsCount = (_posts[idx].commentsCount - 1).clamp(
            0,
            1 << 30,
          );
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Comment deleted')));
    } catch (e) {
      debugPrint('Delete comment failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete comment')));
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchPosts(silent: false);
    _setupAutoUpdates();
    _fetchThreadLockState();
  }

  // ✅ Thread-level moderation state. Individual posts don't carry their
  // parent thread's is_locked flag, so this is a lightweight one-shot
  // fetch just for gating the composer UI — the server independently
  // enforces the lock on every POST regardless of what the client shows.
  bool _threadLocked = false;

  Future<void> _fetchThreadLockState() async {
    try {
      final data = await context.read<ForumRepository>().getThread(
        widget.threadId,
      );
      if (!mounted) return;
      setState(() => _threadLocked = data['is_locked'] == true);
    } catch (e) {
      debugPrint('Could not fetch thread lock state: $e');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _postSubscription?.cancel();
    _commentSubscription?.cancel();
    _bannerTimer?.cancel();
    _scrollController.dispose();

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
          .timeout(const Duration(seconds: 20));

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

    // A timeout on an early attempt is far more likely to be the
    // backend cold-starting than a genuine failure — say so instead of
    // showing a raw error while we're still within the retry budget.
    if (mounted && _retryCount <= _maxRetries) {
      setState(() {
        _errorMessage = message.contains('timed out')
            ? 'Waking up the server — this can take up to a minute on first load.'
            : message;
      });
    }

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
    _showHeartBurst.putIfAbsent(postId, () => false);
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
      final attachmentErrors = await repo.addComment(
        threadId: widget.threadId,
        postId: postId,
        content: text,
        attachments: attachments,
      );

      controller.clear();
      _commentAttachments[postId] = [];

      // refresh comments for this post
      await _fetchCommentsForPost(postId);

      if (mounted) {
        if (attachmentErrors.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Comment posted'),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        } else {
          // Comment saved, but one or more files didn't make it — say so
          // instead of letting the attachment vanish with no explanation.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Comment posted, but ${attachmentErrors.length} file(s) '
                "didn't upload: ${attachmentErrors.join('; ')}",
              ),
              backgroundColor: Colors.orange[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
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

  // ✅ NEW: double-tap-to-like — a pattern this audience already knows
  // instinctively from Instagram/TikTok. Only *likes* (never unlikes) on
  // double-tap, matching that convention, and shows a brief heart burst
  // regardless, so tapping something you already liked still feels good.
  void _onPostDoubleTap(int index) {
    final post = _posts[index];
    if (!post.likedByMe) {
      _toggleLikeOnPost(index);
    }
    setState(() => _showHeartBurst[post.id] = true);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showHeartBurst[post.id] = false);
    });
  }

  // ---------------------------
  // Event bus handlers
  // ---------------------------
  void _onExternalNewPost(ForumPost post) {
    if (!mounted) return;
    if (!_posts.any((p) => p.id == post.id)) {
      setState(() {
        _posts.insert(0, post);
        _ensurePerPostState(post.id);
      });
    }

    // ✅ Real-time "new post" banner instead of a SnackBar — tappable,
    // shows who posted, and scrolls you to it.
    _bannerTimer?.cancel();
    setState(() {
      _latestNewPost = post;
      _showNewPostBanner = true;
    });
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showNewPostBanner = false);
    });
  }

  void _onExternalNewComment(int postId, ForumComment comment) async {
    if (!mounted) return;
    if (_commentsMap.containsKey(postId) && _commentsMap[postId] != null) {
      setState(() {
        _commentsMap[postId]?.insert(0, comment);
      });
    } else {
      await _fetchCommentsForPost(postId, silent: true);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('💬 New comment from ${comment.authorName}'),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    _fetchPosts(silent: true);
  }

  void _dismissBannerAndScrollTop() {
    setState(() => _showNewPostBanner = false);
    _bannerTimer?.cancel();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  // ---------------------------
  // UI building
  // ---------------------------
  Widget _buildAvatar(
    String? avatarUrl,
    String name, {
    double radius = 20,
    bool isBot = false,
    int? authorId,
  }) {
    final color = isBot ? AppColors.inkDusk : _colorForName(name);
    final avatar = GestureDetector(
      onTap: (isBot || authorId == null)
          ? null
          : () => openUserProfile(context, authorId),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: color,
        backgroundImage: avatarUrl != null
            ? NetworkImage(UserRepository.getProfilePictureUrl(avatarUrl))
            : null,
        child: avatarUrl != null
            ? null
            : isBot
            ? const Icon(Icons.auto_awesome, color: Colors.white, size: 18)
            : Text(
                _initialsFor(name),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.7,
                ),
              ),
      ),
    );
    if (!isBot) return avatar;
    // ✅ Small "AI" badge pinned to the avatar corner — content authored
    // by the assistant must never be visually confusable with a real
    // member's post, no matter how the rest of the card renders.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.emberGold,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: const Text(
              'AI',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------
  // Attachment tiles (shared by posts + comments)
  // ---------------------------
  bool _isImageAttachment(ForumAttachment a) =>
      a.mimeType.toLowerCase().startsWith('image/');
  bool _isVideoAttachment(ForumAttachment a) =>
      a.mimeType.toLowerCase().startsWith('video/');

  IconData _iconForDocument(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'txt':
        return Icons.article_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Future<void> _openAttachment(ForumAttachment a) async {
    try {
      final repo = context.read<ForumRepository>();
      await repo.openAttachment(a);
    } catch (e) {
      debugPrint('Could not open attachment ${a.fileName}: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open ${a.fileName}')));
      }
    }
  }

  // ✅ Images and videos now open in an in-app viewer (zoomable image /
  // playable video, same idea as the home feed's media viewer) instead of
  // handing off to the browser or an external app — that made "viewing"
  // an attachment feel like leaving the app rather than reading a post.
  // Documents (pdf/docx/txt/...) still open externally since there's no
  // in-app renderer for those here.
  void _openMediaViewer(ForumAttachment a, {required bool isVideo}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ForumMediaViewerScreen(
          url: ForumRepository.getAttachmentUrl(a.url),
          fileName: a.fileName,
          isVideo: isVideo,
        ),
      ),
    );
  }

  /// Renders one attachment as a `size` x `size` tile: the real thumbnail
  /// for images, a real first-frame thumbnail for videos, and a file icon +
  /// name for everything else (pdf/docx/txt). Images and videos open an
  /// in-app viewer; documents open externally via the OS/browser.
  Widget _buildAttachmentTile(ForumAttachment a, {double size = 96}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileSurface = isDark ? const Color(0xFF332A4D) : AppColors.warmLinen;

    if (_isImageAttachment(a)) {
      return GestureDetector(
        onTap: () => _openMediaViewer(a, isVideo: false),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: ForumRepository.getAttachmentUrl(a.url),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              width: size,
              height: size,
              color: tileSurface,
              alignment: Alignment.center,
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.roseQuartz,
              ),
            ),
            placeholder: (context, url) => Container(
              width: size,
              height: size,
              color: tileSurface,
              alignment: Alignment.center,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.emberGold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_isVideoAttachment(a)) {
      return GestureDetector(
        onTap: () => _openMediaViewer(a, isVideo: true),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _AttachmentVideoThumb(
            url: ForumRepository.getAttachmentUrl(a.url),
            size: size,
          ),
        ),
      );
    }

    // Fallback: pdf/docx/txt/etc — a file icon + truncated name.
    return GestureDetector(
      onTap: () => _openAttachment(a),
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: tileSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _iconForDocument(a.fileName),
              size: 28,
              color: AppColors.emberGold,
            ),
            const SizedBox(height: 4),
            Text(
              a.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _pendingImageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp'};
  static const _pendingVideoExtensions = {
    'mp4',
    'mov',
    'avi',
    'webm',
    'mkv',
    'm4v',
  };

  String _extOf(PlatformFile f) => (f.extension ?? '').toLowerCase();

  /// Thumbnail for a file the user has picked but not yet uploaded.
  /// Only ever hands actual image bytes/paths to Image.memory/Image.file —
  /// videos and documents get an icon instead, since decoding a PDF or
  /// video through Image.* throws at paint time and blanks the screen
  /// (the exact bug already fixed for the new-post form; comments had
  /// the same gap).
  Widget _buildPendingAttachmentThumb(PlatformFile f) {
    final ext = _extOf(f);
    final isImage = _pendingImageExtensions.contains(ext);
    final isVideo = _pendingVideoExtensions.contains(ext);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileSurface = isDark ? const Color(0xFF332A4D) : AppColors.warmLinen;

    if (isImage) {
      Widget? image;
      if (kIsWeb && f.bytes != null) {
        image = Image.memory(f.bytes!, fit: BoxFit.cover);
      } else if (!kIsWeb && f.path != null) {
        image = Image.file(File(f.path!), fit: BoxFit.cover);
      }
      return Container(
        width: 56,
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: tileSurface,
        ),
        child: image ?? Icon(Icons.image_outlined, color: AppColors.emberGold),
      );
    }

    return Container(
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isVideo ? AppColors.inkDusk : tileSurface,
      ),
      alignment: Alignment.center,
      child: isVideo
          ? const Icon(
              Icons.play_circle_fill_rounded,
              color: AppColors.emberGold,
              size: 26,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconForDocument(f.name),
                  size: 20,
                  color: AppColors.emberGold,
                ),
                const SizedBox(height: 2),
                Text(
                  ext.isEmpty ? '?' : ext,
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPostCard(ForumPost post, int index) {
    _ensurePerPostState(post.id);

    final comments = _commentsMap[post.id] ?? [];
    final isVisible = _isCommentsVisible[post.id] ?? false;
    final isLoadingComments = _isCommentsLoading[post.id] ?? false;
    final controller = _commentControllers[post.id]!;
    final attachments = _commentAttachments[post.id] ?? [];
    final isPosting = _isPostingCommentForPost[post.id] ?? false;
    final authorColor = _colorForName(post.authorName);

    // ✅ Real-data-driven popularity badge — no fabricated numbers, just a
    // visual reward for posts that are genuinely getting traction.
    final isPopular = post.likeCount >= 10 || post.commentsCount >= 5;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      // The app's signature "chapel doorway" arch — restoring the shared
      // cardTheme shape instead of overriding it with a generic rounded
      // rectangle, so this screen actually matches the rest of the app.
      shape: AppShapes.archBorder().copyWith(
        side: BorderSide(color: authorColor.withOpacity(0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Row(
              children: [
                _buildAvatar(
                  post.authorAvatar,
                  post.authorName,
                  isBot: post.authorIsBot,
                  authorId: post.authorId,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.authorName,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: authorColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPopular) ...[
                            const SizedBox(width: 6),
                            const Text('🔥', style: TextStyle(fontSize: 13)),
                          ],
                        ],
                      ),
                      if (post.createdAt != null)
                        Text(
                          _formatDate(post.createdAt!),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.55),
                              ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  onSelected: (value) {
                    if (value == 'delete') _deletePost(post);
                    if (value == 'report') _reportPost(post);
                    if (value == 'ai_reply') _askAssistantToReply(post);
                  },
                  itemBuilder: (_) => [
                    if (_isStaff() && !post.authorIsBot)
                      const PopupMenuItem(
                        value: 'ai_reply',
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 18),
                            SizedBox(width: 8),
                            Text('Ask assistant to reply'),
                          ],
                        ),
                      ),
                    if (!_canManage(post.authorId))
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Report post'),
                          ],
                        ),
                      ),
                    if (_canManage(post.authorId))
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: Color(0xFFC94C40),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Delete post',
                              style: TextStyle(color: Color(0xFFC94C40)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // content — double-tap to like, with heart burst overlay
            GestureDetector(
              onDoubleTap: () => _onPostDoubleTap(index),
              behavior: HitTestBehavior.opaque,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.content,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (post.attachments.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: post.attachments
                              .map((a) => _buildAttachmentTile(a))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                  // ✅ Heart burst — classic double-tap delight moment
                  AnimatedOpacity(
                    opacity: (_showHeartBurst[post.id] ?? false) ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedScale(
                      scale: (_showHeartBurst[post.id] ?? false) ? 1.0 : 0.5,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.elasticOut,
                      child: const Icon(
                        Icons.favorite,
                        color: AppColors.roseQuartz,
                        size: 84,
                        shadows: [
                          Shadow(color: Colors.black26, blurRadius: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // engagement row — pill-shaped, colored when active
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _toggleLikeOnPost(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: post.likedByMe
                          ? AppColors.roseQuartz.withOpacity(0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        AnimatedScale(
                          scale: post.likedByMe ? 1.15 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            post.likedByMe
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: post.likedByMe
                                ? AppColors.roseQuartz
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.5),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${post.likeCount}',
                          style: TextStyle(
                            color: post.likedByMe
                                ? AppColors.roseQuartz
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _toggleCommentsForPost(post.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isVisible
                          ? AppColors.verdantSage.withOpacity(0.14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 18,
                          color: isVisible
                              ? AppColors.verdantSage
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${post.commentsCount}',
                          style: TextStyle(
                            color: isVisible
                                ? AppColors.verdantSage
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          isVisible ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // comments panel (animated)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  Divider(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.08),
                  ),
                  if (isLoadingComments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.emberGold,
                        ),
                      ),
                    )
                  else if (comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.mode_comment_outlined,
                            color: AppColors.verdantSage.withOpacity(0.5),
                            size: 28,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No comments yet. Be the first to comment!',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.55),
                            ),
                          ),
                        ],
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
                      height: 64,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: attachments.map((f) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _buildPendingAttachmentThumb(f),
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
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            Theme.of(context).cardTheme.color ??
                                            Colors.white,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.15,
                                            ),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Color(0xFFC94C40),
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

                  if (_threadLocked && !_isStaff())
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'This thread is locked — no new replies',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.attach_file,
                            color: AppColors.emberGold,
                          ),
                          onPressed: () => _pickAttachmentsForPost(post.id),
                        ),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration: InputDecoration(
                              hintText: 'Write a comment...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const Color(0xFF332A4D)
                                  : AppColors.warmLinen,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                            minLines: 1,
                            maxLines: 3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        isPosting
                            ? SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.emberGold,
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.send),
                                color: AppColors.emberGold,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: isDark ? const Color(0xFF332A4D) : AppColors.warmLinen,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: _buildAvatar(
          comment.authorAvatar,
          comment.authorName,
          radius: 16,
          isBot: comment.authorIsBot,
          authorId: comment.authorId,
        ),
        title: Text(
          comment.authorName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 14,
            color: _colorForName(comment.authorName),
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
          onSelected: (value) {
            if (value == 'delete') _deleteComment(comment);
            if (value == 'report') _reportComment(comment);
          },
          itemBuilder: (_) => [
            if (!_canManage(comment.authorId))
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Report'),
                  ],
                ),
              ),
            if (_canManage(comment.authorId))
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Color(0xFFC94C40),
                    ),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Color(0xFFC94C40))),
                  ],
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(
              comment.content,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (comment.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: comment.attachments
                      .map((a) => _buildAttachmentTile(a, size: 56))
                      .toList(),
                ),
              ),
            if (comment.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _formatDate(comment.createdAt!),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
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
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.roseQuartz.withOpacity(0.14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 40,
                  color: AppColors.roseQuartz,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Connection Issue',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Unable to connect to server',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
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
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPostsBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.emberGold.withOpacity(0.14),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.forum_outlined,
                size: 40,
                color: AppColors.emberGold,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Posts Yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to start a discussion in this thread!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final created = await context.push(
                  '/threads/${widget.threadId}/new-post',
                  extra: {
                    'threadId': widget.threadId,
                    'threadTitle': widget.threadTitle,
                  },
                );
                if (created == true) _fetchPosts();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Start the discussion'),
            ),
          ],
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
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_threadLocked) ...[
                  const Icon(Icons.lock_outline, size: 16),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    widget.threadTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (!_isLoadingPosts && _posts.isNotEmpty)
              Text(
                '${_posts.length} post${_posts.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_isStaff())
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'toggle_lock') {
                  final ok = await context
                      .read<ForumRepository>()
                      .setThreadModeration(
                        widget.threadId,
                        isLocked: !_threadLocked,
                      );
                  if (ok && mounted)
                    setState(() => _threadLocked = !_threadLocked);
                } else if (value == 'ai_reflection') {
                  _promptAssistantThreadPost();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle_lock',
                  child: Row(
                    children: [
                      Icon(
                        _threadLocked ? Icons.lock_open : Icons.lock_outline,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(_threadLocked ? 'Unlock thread' : 'Lock thread'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'ai_reflection',
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 18),
                      SizedBox(width: 8),
                      Text('Ask assistant for a reflection post'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: (_threadLocked && !_isStaff())
          ? null
          : RoleGuard(
              roles: ['member', 'admin', 'moderator'],
              child: FloatingActionButton.extended(
                onPressed: () async {
                  final created = await context.push(
                    '/threads/${widget.threadId}/new-post',
                    extra: {
                      'threadId': widget.threadId,
                      'threadTitle': widget.threadTitle,
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
      body: Stack(
        children: [
          _isLoadingPosts
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.emberGold),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : _errorMessage != null
              ? _buildErrorBody()
              : _posts.isEmpty
              ? RefreshIndicator(
                  onRefresh: _fetchPosts,
                  color: AppColors.emberGold,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: _buildEmptyPostsBody(),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchPosts,
                  color: AppColors.emberGold,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _posts.length,
                    itemBuilder: (context, i) => _buildPostCard(_posts[i], i),
                  ),
                ),

          // ✅ "New post" live banner — the ink-dusk-to-ember-gold gradient
          // is the same "golden hour" motif used on the splash screen, so
          // the live moment feels like part of this app's identity rather
          // than a stock Material snackbar.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            top: _showNewPostBanner ? 12 : -80,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: _dismissBannerAndScrollTop,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.inkDusk, AppColors.emberGold],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.arrow_upward,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _latestNewPost != null
                              ? 'New post from ${_latestNewPost!.authorName}'
                              : 'New post',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// VIDEO ATTACHMENT THUMBNAIL
// ==========================================

/// A `size` x `size` tile showing the video's real first frame (paused)
/// with a play badge on top, instead of a flat placeholder box — replaces
/// the old solid-color-plus-icon tile with something that actually looks
/// like the video it represents.
class _AttachmentVideoThumb extends StatefulWidget {
  final String url;
  final double size;

  const _AttachmentVideoThumb({required this.url, required this.size});

  @override
  State<_AttachmentVideoThumb> createState() => _AttachmentVideoThumbState();
}

class _AttachmentVideoThumbState extends State<_AttachmentVideoThumb> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      // Land on the first frame and stay paused — this is a thumbnail,
      // not an autoplaying preview.
      await controller.seekTo(Duration.zero);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      debugPrint('Video thumbnail failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      color: AppColors.inkDusk,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          if (_ready && _controller != null)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else if (_failed)
            const Icon(Icons.videocam_off_outlined, color: AppColors.roseQuartz)
          else
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.emberGold,
              ),
            ),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.35),
            ),
            padding: const EdgeInsets.all(6),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// IN-APP MEDIA VIEWER
// ==========================================

/// Full-screen viewer opened when an image or video attachment is tapped.
/// Images get a zoomable `InteractiveViewer`; videos get a real player with
/// tap-to-play/pause. Both keep a "download/open" action for anyone who
/// wants the file itself, but viewing no longer requires leaving the app.
class _ForumMediaViewerScreen extends StatefulWidget {
  final String url;
  final String fileName;
  final bool isVideo;

  const _ForumMediaViewerScreen({
    required this.url,
    required this.fileName,
    required this.isVideo,
  });

  @override
  State<_ForumMediaViewerScreen> createState() =>
      _ForumMediaViewerScreenState();
}

class _ForumMediaViewerScreenState extends State<_ForumMediaViewerScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _setUpVideo();
  }

  Future<void> _setUpVideo() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _initialized = true);
      controller.play();
    } catch (e) {
      debugPrint('Media viewer video failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _downloadOrOpen() async {
    final uri = Uri.parse(widget.url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download / open',
            onPressed: _downloadOrOpen,
          ),
        ],
      ),
      body: Center(child: widget.isVideo ? _buildVideo() : _buildImage()),
    );
  }

  Widget _buildImage() {
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 4,
      child: CachedNetworkImage(
        imageUrl: widget.url,
        fit: BoxFit.contain,
        errorWidget: (context, url, error) => const Icon(
          Icons.broken_image_outlined,
          color: AppColors.roseQuartz,
          size: 48,
        ),
        placeholder: (context, url) =>
            const CircularProgressIndicator(color: Colors.white70),
      ),
    );
  }

  Widget _buildVideo() {
    if (_failed) {
      return const Icon(
        Icons.videocam_off_outlined,
        color: AppColors.roseQuartz,
        size: 48,
      );
    }
    if (!_initialized || _controller == null) {
      return const CircularProgressIndicator(color: Colors.white70);
    }
    final controller = _controller!;
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: GestureDetector(
        onTap: () => setState(() {
          controller.value.isPlaying ? controller.pause() : controller.play();
        }),
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            VideoPlayer(controller),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => controller.value.isPlaying
                  ? const SizedBox.shrink()
                  : const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 64,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
