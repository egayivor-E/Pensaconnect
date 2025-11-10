import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/repositories/forum_repository.dart';
import '../models/forum_model.dart';
import '../utils/role_utils.dart';

class PostDetailScreen extends StatefulWidget {
  final int threadId; // ✅ add this
  final int postId;

  const PostDetailScreen({
    super.key,
    required this.threadId,
    required this.postId,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _repo = ForumRepository();
  late Future<ForumPost> _postFuture;
  late Future<List<ForumComment>> _commentsFuture;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _postFuture = _repo.getPost(
      widget.postId,
    ); // <-- make sure your repo exposes this
    _commentsFuture = _repo.getComments(widget.postId); // <-- and this
    setState(() {});
  }

  Future<void> _sendComment() async {
    if (_commentCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await _repo.addComment(
        threadId: widget.threadId,
        postId: widget.postId,
        content: _commentCtrl.text.trim(),
        attachments: const [], // add picker later if you want
      );
      _commentCtrl.clear();
      _reload();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _toggleLike() async {
    await _repo.toggleLike(widget.postId);
    _reload();
  }

  Future<void> _approve() async {
    await _repo.approvePost(widget.postId);
    _reload();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repo.deletePost(widget.postId);
      if (mounted) if (!mounted) return;
      if (!mounted) return;
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: FutureBuilder<ForumPost>(
        future: _postFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData) {
            return const Center(child: Text('Post not found'));
          }
          final post = snap.data!;

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        post.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text('by ${post.authorName}'),
                      const SizedBox(height: 12),
                      Text(post.content),
                      const SizedBox(height: 12),

                      // Attachments
                      if (post.attachments.isNotEmpty) ...[
                        const Divider(),
                        const Text(
                          'Attachments',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ...post.attachments.map(
                          (a) => ListTile(
                            leading: const Icon(Icons.attach_file),
                            title: Text(a.fileName),
                            subtitle: Text(a.mimeType),
                            onTap: () =>
                                _repo.openAttachment(a), // optionally implement
                          ),
                        ),
                      ],

                      const Divider(height: 24),

                      // Actions row
                      Row(
                        children: [
                          IconButton(
                            onPressed: _toggleLike,
                            icon: Icon(
                              post.likedByMe
                                  ? Icons.thumb_up
                                  : Icons.thumb_up_outlined,
                            ),
                          ),
                          Text('${post.likeCount}'),
                          const Spacer(),
                          RoleGuard(
                            roles: const ['moderator', 'admin'],
                            child: IconButton(
                              onPressed: _approve,
                              icon: const Icon(Icons.check_circle),
                              tooltip: 'Approve',
                            ),
                          ),
                          RoleGuard(
                            roles: const ['admin'],
                            child: IconButton(
                              onPressed: _delete,
                              icon: const Icon(Icons.delete),
                              tooltip: 'Delete',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Comments
                      Text(
                        'Comments',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<ForumComment>>(
                        future: _commentsFuture,
                        builder: (context, csnap) {
                          if (csnap.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final comments = csnap.data ?? [];
                          if (comments.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: Text('No comments yet.')),
                            );
                          }
                          return Column(
                            children: comments
                                .map(
                                  (c) => ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.person),
                                    ),
                                    title: Text(c.authorName),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(c.content),
                                        if (c.attachments.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Wrap(
                                              spacing: 8,
                                              children: c.attachments
                                                  .map(
                                                    (a) => Chip(
                                                      label: Text(a.fileName),
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Add comment field
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentCtrl,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Write a comment…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _submitting
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed: _sendComment,
                              icon: const Icon(Icons.send),
                            ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
