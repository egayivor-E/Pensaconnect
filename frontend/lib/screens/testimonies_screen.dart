import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/testimony_model.dart';
import '../repositories/testimony_repository.dart';
import '../services/auth_service.dart';

class TestimoniesScreen extends StatefulWidget {
  const TestimoniesScreen({super.key});

  @override
  State<TestimoniesScreen> createState() => _TestimoniesScreenState();
}

class _TestimoniesScreenState extends State<TestimoniesScreen> {
  final _repo = TestimonyRepository();
  late Future<List<Testimony>> _future;

  // ✅ Same identity-color system used across forums/groups, so a given
  // person is visually consistent everywhere in the app.
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

  // ✅ FIX: previously the delete icon was shown on every card regardless
  // of who was viewing it — meaning any logged-in user could delete any
  // OTHER user's testimony. This now compares the testimony's real
  // `authorId` (confirmed present on the Testimony model) against the
  // logged-in user's id, instead of the earlier username-based proxy.
  // authorId is a String on the model, AuthService().userId is an int?,
  // so both sides are normalized to string for the comparison.
  bool _canDelete(Testimony t) {
    final auth = AuthService();
    if (auth.isAdmin) return true;
    final myId = auth.userId;
    if (myId == null || t.authorId.isEmpty) return false;
    return t.authorId == myId.toString();
  }

  final Map<String, bool> _showHeartBurst = {};

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchTestimonies();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _repo.fetchTestimonies(forceRefresh: true);
    });
    await _future;
  }

  Future<void> _deleteTestimony(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Testimony?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repo.deleteTestimony(id);
        if (mounted) _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  Future<void> _toggleLike(Testimony testimony, int index) async {
    try {
      await _repo.toggleLike(int.parse(testimony.id));
      setState(() {
        _future = _repo.fetchTestimonies();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to like: $e')));
      }
    }
  }

  void _onCardDoubleTap(Testimony t, int index) {
    if (!t.likedByMe) {
      _toggleLike(t, index);
    }
    setState(() => _showHeartBurst[t.id] = true);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showHeartBurst[t.id] = false);
    });
  }

  void _navigateToComments(Testimony testimony) async {
    await context.push('/testimonies/${testimony.id}');
    if (mounted) {
      setState(() {
        _future = _repo.fetchTestimonies();
      });
    }
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_outlined, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No testimonies yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Someone\'s story could encourage someone else\ntoday. Yours might be the first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await context.push('/testimonies/add');
                if (mounted) {
                  setState(() => _future = _repo.fetchTestimonies());
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Share your story'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Testimonies & Stories')),
      body: FutureBuilder<List<Testimony>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('❌ Error fetching testimonies: ${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('Failed to load testimonies.'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final testimonies = snapshot.data ?? [];
          if (testimonies.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: _buildEmptyState(theme),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: testimonies.length,
              itemBuilder: (context, index) {
                final t = testimonies[index];
                final color = _colorForName(t.authorName);
                final isPopular = t.likesCount >= 10 || t.commentsCount >= 5;
                final canDelete = _canDelete(t);

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: color.withOpacity(0.15)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      await context.push('/testimonies/${t.id}');
                      if (mounted) {
                        setState(() {
                          _future = _repo.fetchTestimonies();
                        });
                      }
                    },
                    onDoubleTap: () => _onCardDoubleTap(t, index),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            if (t.imageUrl != null)
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                                child: Image.network(
                                  t.imageUrl!,
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 160,
                                      width: double.infinity,
                                      color: Colors.grey[200],
                                      child: const Icon(
                                        Icons.broken_image,
                                        color: Colors.grey,
                                        size: 50,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            // ✅ Heart burst on double-tap — same delight
                            // pattern as the forums screens, so the gesture
                            // is consistent (and therefore addictive in a
                            // healthy, learned-muscle-memory way) across
                            // the whole app.
                            AnimatedOpacity(
                              opacity: (_showHeartBurst[t.id] ?? false) ? 1 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: AnimatedScale(
                                scale: (_showHeartBurst[t.id] ?? false) ? 1.0 : 0.5,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.elasticOut,
                                child: const Icon(
                                  Icons.favorite,
                                  color: Colors.redAccent,
                                  size: 72,
                                  shadows: [Shadow(color: Colors.black38, blurRadius: 12)],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            t.title,
                                            style: theme.textTheme.titleLarge
                                                ?.copyWith(fontWeight: FontWeight.bold),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isPopular) ...[
                                          const SizedBox(width: 6),
                                          const Text('🔥', style: TextStyle(fontSize: 14)),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // ✅ Delete now hidden unless you're the
                                  // author or an admin, and tucked into a
                                  // low-key overflow menu instead of a
                                  // loud red icon on every card.
                                  if (canDelete)
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 20),
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _deleteTestimony(int.parse(t.id));
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                              SizedBox(width: 8),
                                              Text('Delete', style: TextStyle(color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t.content.length > 100
                                    ? '${t.content.substring(0, 100)}...'
                                    : t.content,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, height: 1.3),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: color,
                                    child: Text(
                                      _initialsFor(t.authorName),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t.authorName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    t.createdAt.toLocal().toString().split(" ").first,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _toggleLike(t, index),
                                    borderRadius: BorderRadius.circular(20),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: t.likedByMe
                                            ? theme.colorScheme.primary.withOpacity(0.12)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        children: [
                                          AnimatedScale(
                                            scale: t.likedByMe ? 1.15 : 1.0,
                                            duration: const Duration(milliseconds: 200),
                                            child: Icon(
                                              t.likedByMe ? Icons.thumb_up : Icons.thumb_up_outlined,
                                              size: 18,
                                              color: t.likedByMe ? theme.colorScheme.primary : Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${t.likesCount}',
                                            style: TextStyle(
                                              color: t.likedByMe ? theme.colorScheme.primary : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _navigateToComments(t),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.chat_bubble_outline, size: 17, color: Colors.grey),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${t.commentsCount}',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/testimonies/add');
          if (mounted) {
            setState(() {
              _future = _repo.fetchTestimonies();
            });
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Share'),
      ),
    );
  }
}
