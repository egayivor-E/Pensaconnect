import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/forum_model.dart';
import '../repositories/forum_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _posts = _repo.getPosts(widget.threadId); // ✅ fixed positional argument
  }

  @override
  Widget build(BuildContext context) {
    final userRoles = ["member"]; // TODO: Replace with AuthProvider roles

    return Scaffold(
      appBar: AppBar(title: const Text("Posts")),

      body: FutureBuilder<List<ForumPost>>(
        future: _posts,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No posts yet"));
          }

          final posts = snapshot.data!;
          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, i) {
              final post = posts[i];
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(
                    post.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    post.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    // ✅ Navigate with go_router
                    context.push(
                      "/posts/${post.id}",
                      extra: post, // pass full post object to PostDetailScreen
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton:
          userRoles.contains("member") || userRoles.contains("admin")
          ? FloatingActionButton(
              onPressed: () {
                // ✅ Navigate with go_router to post form
                context.push(
                  "/threads/${widget.threadId}/new-post",
                  extra: widget.threadId,
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
