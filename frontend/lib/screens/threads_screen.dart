import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pensaconnect/repositories/user_repository.dart';
import 'package:provider/provider.dart';
import 'package:animations/animations.dart';
import '../providers/threads_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/role_utils.dart';

class ThreadsScreen extends StatefulWidget {
  const ThreadsScreen({super.key});

  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _sortLabel(String sort) {
    switch (sort) {
      case 'active':
        return 'Most active';
      case 'liked':
        return 'Most liked';
      default:
        return 'Newest';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final threadsProvider = context.watch<ThreadsProvider>();
    final authProvider = context.read<AuthProvider>();
    final isStaff = authProvider.hasAnyRole(const ['admin', 'moderator']);

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

      body: Column(
        children: [
          // --- Search + sort bar ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search threads…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                threadsProvider.setSearchQuery('');
                                setState(() {});
                              },
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) => threadsProvider.setSearchQuery(v),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Sort threads',
                  initialValue: threadsProvider.sort,
                  onSelected: (v) => threadsProvider.setSort(v),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'newest', child: Text('Newest')),
                    PopupMenuItem(value: 'active', child: Text('Most active')),
                    PopupMenuItem(value: 'liked', child: Text('Most liked')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sort_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _sortLabel(threadsProvider.sort),
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: threadsProvider.isLoading
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
                            itemCount: threadsProvider.threads.length + 1,
                            itemBuilder: (context, rawIndex) {
                              if (rawIndex == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Text(
                                    'Tap a thread to read the full conversation and post your own reply.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.55),
                                    ),
                                  ),
                                );
                              }
                              final index = rawIndex - 1;
                              final t = threadsProvider.threads[index];

                              final int likeCount = t['like_count'] ?? 0;
                              final int dislikeCount = t['dislike_count'] ?? 0;
                              // Backend returns forum_posts_count (posts_count is
                              // the legacy pre-migration Post model's count).
                              final int postCount = t['forum_posts_count'] ?? 0;
                              final bool likedByMe = t['liked_by_me'] ?? false;
                              final bool dislikedByMe =
                                  t['disliked_by_me'] ?? false;

                              return OpenContainer(
                                closedElevation: 0,
                                openElevation: 0,
                                transitionType:
                                    ContainerTransitionType.fadeThrough,
                                closedColor: theme.colorScheme.surface,
                                openColor: theme.colorScheme.surface,
                                closedBuilder: (context, openContainer) {
                                  return GestureDetector(
                                    onTap: () {
                                      context.push(
                                        "/threads/${t['id']}",
                                        extra: {
                                          'id': t['id'],
                                          'title': t['title'],
                                        },
                                      );
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 14),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.05,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // --- Title + pin/lock badges + staff menu ---
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (t['is_pinned'] == true)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    right: 6,
                                                    top: 2,
                                                  ),
                                                  child: Icon(
                                                    Icons.push_pin_rounded,
                                                    size: 16,
                                                    color: Colors.amber,
                                                  ),
                                                ),
                                              if (t['is_locked'] == true)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 6,
                                                        top: 2,
                                                      ),
                                                  child: Icon(
                                                    Icons.lock_rounded,
                                                    size: 16,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  t['title'] ??
                                                      'Untitled Thread',
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 18,
                                                      ),
                                                ),
                                              ),
                                              if (isStaff)
                                                PopupMenuButton<String>(
                                                  padding: EdgeInsets.zero,
                                                  icon: Icon(
                                                    Icons.more_vert_rounded,
                                                    size: 18,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                  onSelected: (action) {
                                                    final pinned =
                                                        t['is_pinned'] == true;
                                                    final locked =
                                                        t['is_locked'] == true;
                                                    if (action == 'pin') {
                                                      threadsProvider.togglePin(
                                                        t['id'],
                                                        !pinned,
                                                      );
                                                    } else if (action ==
                                                        'lock') {
                                                      threadsProvider
                                                          .toggleLock(
                                                            t['id'],
                                                            !locked,
                                                          );
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    PopupMenuItem(
                                                      value: 'pin',
                                                      child: Text(
                                                        t['is_pinned'] == true
                                                            ? 'Unpin thread'
                                                            : 'Pin thread',
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'lock',
                                                      child: Text(
                                                        t['is_locked'] == true
                                                            ? 'Unlock thread'
                                                            : 'Lock thread',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),

                                          // --- Description ---
                                          if (t['description'] != null &&
                                              t['description']
                                                  .trim()
                                                  .isNotEmpty)
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
                                                    t['author_avatar'] !=
                                                            null &&
                                                        t['author_avatar']
                                                            .isNotEmpty
                                                    ? NetworkImage(
                                                        UserRepository.getProfilePictureUrl(
                                                          t['author_avatar'],
                                                        ), // ← REUSE!
                                                      )
                                                    : null,
                                                child:
                                                    t['author_avatar'] == null
                                                    ? const Icon(
                                                        Icons
                                                            .person_outline_rounded,
                                                        size: 18,
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                t['author_name'] ??
                                                    'Unknown User',
                                                style: theme
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              const Spacer(),
                                              Icon(
                                                Icons
                                                    .chat_bubble_outline_rounded,
                                                size: 16,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '$postCount',
                                                style:
                                                    theme.textTheme.labelMedium,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Divider(
                                            color: theme.dividerColor
                                                .withOpacity(0.4),
                                          ),

                                          // --- Reaction Row ---
                                          Row(
                                            children: [
                                              // 👍 Like
                                              IconButton(
                                                icon: Icon(
                                                  likedByMe
                                                      ? Icons.thumb_up_rounded
                                                      : Icons
                                                            .thumb_up_alt_outlined,
                                                  size: 20,
                                                  color: likedByMe
                                                      ? theme
                                                            .colorScheme
                                                            .primary
                                                      : theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                ),
                                                onPressed: () async {
                                                  await threadsProvider
                                                      .toggleLike(t['id']);
                                                },
                                              ),
                                              Text(
                                                '$likeCount',
                                                style:
                                                    theme.textTheme.labelMedium,
                                              ),

                                              const SizedBox(width: 8),

                                              // 👎 Dislike
                                              IconButton(
                                                icon: Icon(
                                                  dislikedByMe
                                                      ? Icons.thumb_down_rounded
                                                      : Icons
                                                            .thumb_down_alt_outlined,
                                                  size: 20,
                                                  color: dislikedByMe
                                                      ? Colors.redAccent
                                                      : theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                ),
                                                onPressed: () async {
                                                  await threadsProvider
                                                      .toggleDislike(t['id']);
                                                },
                                              ),
                                              Text(
                                                '$dislikeCount',
                                                style:
                                                    theme.textTheme.labelMedium,
                                              ),
                                            ],
                                          ),

                                          // ✅ NEW: an explicit "open the thread"
                                          // footer, so the card doesn't rely on
                                          // people intuiting that a whole tap
                                          // target opens somewhere — it names the
                                          // destination and what you can do there
                                          // (read replies, post one) and gives a
                                          // chevron as a standard "this goes
                                          // somewhere" cue.
                                          const SizedBox(height: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 9,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary
                                                  .withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons
                                                      .chat_bubble_outline_rounded,
                                                  size: 16,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    postCount == 0
                                                        ? 'Open thread to post the first reply'
                                                        : 'View $postCount repl${postCount == 1 ? 'y' : 'ies'} · Others view, Join',
                                                    style: theme
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .primary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.arrow_forward_rounded,
                                                  size: 16,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                              ],
                                            ),
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
          ),
        ],
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
