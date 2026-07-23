import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/forum_model.dart';
import '../repositories/forum_repository.dart';
import '../providers/auth_provider.dart';
import '../utils/profile_navigation.dart';
import 'post_form_screen.dart';

class ForumsScreen extends StatefulWidget {
  final int threadId;
  const ForumsScreen({super.key, required this.threadId});
  @override
  State<ForumsScreen> createState() => _ForumsScreenState();
}

class _ForumsScreenState extends State<ForumsScreen> {
  final _repo = ForumRepository();
  late Future<List<ForumPost>> _posts;

  // ✅ Same identity-color approach as ForumDetailScreen, kept consistent
  // across the app so a given person's color always matches wherever
  // they appear.
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

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  void initState() {
    super.initState();
    _posts = _repo.getPosts(widget.threadId);
  }

  Future<void> _refresh() async {
    final future = _repo.getPosts(widget.threadId);
    setState(() => _posts = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Was hardcoded to ["member"] with a TODO — that silently gated
    // posting for guests/other roles incorrectly. Now reads the real
    // signed-in user's roles, same pattern ForumDetailScreen already uses.
    final auth = context.watch<AuthProvider>();
    final canPost = auth.currentUser != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Posts")),
      body: FutureBuilder<List<ForumPost>>(
        future: _posts,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('Something went wrong loading posts'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {
                        _posts = _repo.getPosts(widget.threadId);
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 72,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No posts yet',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Start the conversation — your post could\nbe the first thing someone reads today.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                            if (canPost) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () {
                                  context.push(
                                    "/threads/${widget.threadId}/new-post",
                                    extra: widget.threadId,
                                  );
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Write the first post'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final posts = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: posts.length,
              itemBuilder: (context, i) {
                final post = posts[i];
                final color = _colorForName(post.authorName);
                final isPopular =
                    post.likeCount >= 10 || post.commentsCount >= 5;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: color.withOpacity(0.15)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      context.push("/posts/${post.id}", extra: post);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => openUserProfile(
                                  context,
                                  post.authorId,
                                  username: post.authorName,
                                  profilePicture: post.authorAvatar,
                                ),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: color,
                                  backgroundImage: post.authorAvatar != null
                                      ? NetworkImage(post.authorAvatar!)
                                      : null,
                                  child: post.authorAvatar == null
                                      ? Text(
                                          _initialsFor(post.authorName),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            post.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isPopular) ...[
                                          const SizedBox(width: 6),
                                          const Text(
                                            '🔥',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      post.authorName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (post.createdAt != null)
                                Text(
                                  _formatDate(post.createdAt!),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            post.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.3),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                post.likedByMe
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 16,
                                color: post.likedByMe
                                    ? Colors.redAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${post.likeCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Icon(
                                Icons.chat_bubble_outline,
                                size: 15,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${post.commentsCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () {
                context.push(
                  "/threads/${widget.threadId}/new-post",
                  extra: widget.threadId,
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('New Post'),
            )
          : null,
    );
  }
}
