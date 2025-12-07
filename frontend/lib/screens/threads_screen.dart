import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/repositories/user_repository.dart';
import 'package:provider/provider.dart';
import 'package:animations/animations.dart';
import '../providers/threads_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/role_utils.dart';

class ThreadsScreen extends StatelessWidget {
  const ThreadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final threadsProvider = context.watch<ThreadsProvider>();
    // ignore: unused_local_variable
    final authProvider = context.read<AuthProvider>();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          'Community Threads',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.replace('/home');
            }
          },
        ),
      ),

      body: threadsProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => threadsProvider.fetchThreads(),
              child: threadsProvider.threads.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 72,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No threads yet",
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Be the first to start a conversation!",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: threadsProvider.threads.length,
                      itemBuilder: (context, index) {
                        final t = threadsProvider.threads[index];

                        final int likeCount = t['like_count'] ?? 0;
                        final int dislikeCount = t['dislike_count'] ?? 0;
                        final int postCount = t['post_count'] ?? 0;
                        final bool likedByMe = t['liked_by_me'] ?? false;
                        final bool dislikedByMe = t['disliked_by_me'] ?? false;

                        return OpenContainer(
                          closedElevation: 0,
                          openElevation: 0,
                          transitionType: ContainerTransitionType.fadeThrough,
                          closedColor: theme.colorScheme.surface,
                          openColor: theme.colorScheme.surface,
                          closedBuilder: (context, openContainer) {
                            return GestureDetector(
                              onTap: () {
                                context.push(
                                  "/threads/${t['id']}",
                                  extra: {'id': t['id'], 'title': t['title']},
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // --- Title ---
                                    Text(
                                      t['title'] ?? 'Untitled Thread',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 18,
                                          ),
                                    ),
                                    const SizedBox(height: 6),

                                    // --- Description ---
                                    if (t['description'] != null &&
                                        t['description'].trim().isNotEmpty)
                                      Text(
                                        t['description'],
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              height: 1.4,
                                            ),
                                      ),
                                    const SizedBox(height: 12),

                                    // --- Author + Posts ---
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundImage:
                                              t['author_avatar'] != null &&
                                                  t['author_avatar'].isNotEmpty
                                              ? NetworkImage(
                                                  UserRepository.getProfilePictureUrl(
                                                    t['author_avatar'],
                                                  ), // ← REUSE!
                                                )
                                              : null,
                                          child: t['author_avatar'] == null
                                              ? const Icon(
                                                  Icons.person_outline_rounded,
                                                  size: 18,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          t['author_name'] ?? 'Unknown User',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          Icons.chat_bubble_outline_rounded,
                                          size: 16,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$postCount',
                                          style: theme.textTheme.labelMedium,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Divider(
                                      color: theme.dividerColor.withOpacity(
                                        0.4,
                                      ),
                                    ),

                                    // --- Reaction Row ---
                                    Row(
                                      children: [
                                        // 👍 Like
                                        IconButton(
                                          icon: Icon(
                                            likedByMe
                                                ? Icons.thumb_up
                                                : Icons.thumb_up_alt_outlined,
                                            color: likedByMe
                                                ? theme.colorScheme.primary
                                                : theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                          onPressed: () async {
                                            await threadsProvider.toggleLike(
                                              t['id'],
                                            );
                                          },
                                        ),
                                        Text(
                                          '$likeCount',
                                          style: theme.textTheme.labelMedium,
                                        ),

                                        const SizedBox(width: 8),

                                        // 👎 Dislike
                                        IconButton(
                                          icon: Icon(
                                            dislikedByMe
                                                ? Icons.thumb_down
                                                : Icons.thumb_down_alt_outlined,
                                            color: dislikedByMe
                                                ? Colors.redAccent
                                                : theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                          onPressed: () async {
                                            await threadsProvider.toggleDislike(
                                              t['id'],
                                            );
                                          },
                                        ),
                                        Text(
                                          '$dislikeCount',
                                          style: theme.textTheme.labelMedium,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          openBuilder: (context, _) => const SizedBox(),
                        );
                      },
                    ),
            ),

      floatingActionButton: RoleGuard(
        roles: ["admin", "moderator", "member"],
        child: FloatingActionButton.extended(
          backgroundColor: theme.colorScheme.primary,
          icon: const Icon(Icons.add_rounded, size: 24),
          label: const Text(
            "New Thread",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: () async {
            final created = await context.push<bool>("/threads/new");
            if (created == true) {
              await threadsProvider.fetchThreads();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Thread created successfully!"),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }
}
