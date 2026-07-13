// screens/testimonies_screen.dart
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;

/// A single piece of media attached to a testimony/post.
class PostMedia {
  final File? file;
  final String? networkUrl;
  final bool isVideo;
  const PostMedia({this.file, this.networkUrl, this.isVideo = false});

  ImageProvider get thumbnailProvider => file != null
      ? FileImage(file!) as ImageProvider
      : NetworkImage(networkUrl!);
}

class Testimony {
  final String id;
  final String title;
  final String content;
  final String author;
  final String? authorAvatar;
  final bool anonymous;
  final DateTime createdAt;
  final List<PostMedia> media;
  int likes;
  int commentCount;

  Testimony({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    this.authorAvatar,
    this.anonymous = false,
    DateTime? createdAt,
    List<PostMedia>? media,
    this.likes = 0,
    this.commentCount = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       media = media ?? [];

  String get displayName => anonymous ? 'Anonymous' : author;
}

/// Seed data so the feed doesn't start empty. Replace with a real
/// repository call once the backend "posts" endpoint is available.
List<Testimony> _seedTestimonies() => [
  Testimony(
    id: 't1',
    title: 'God provided right on time',
    content:
        'Last month I was going through a very difficult season. I had just lost my job and was struggling to pay my bills. That night I prayed like never before, and the next morning I got a call offering me an even better position. God is faithful!',
    author: 'Grace Mensah',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    media: const [
      PostMedia(networkUrl: 'https://picsum.photos/seed/testify1/700/500'),
    ],
    likes: 24,
    commentCount: 8,
  ),
  Testimony(
    id: 't2',
    title: 'Healed after months of prayer',
    content:
        'After months of the youth group praying for my recovery, I finally got the all-clear from my doctor this week. Thank you all for standing with me in faith — I felt every prayer.',
    author: 'Kwame Owusu',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    media: const [
      PostMedia(networkUrl: 'https://picsum.photos/seed/testify2/700/500'),
      PostMedia(networkUrl: 'https://picsum.photos/seed/testify2b/700/500'),
    ],
    likes: 41,
    commentCount: 12,
  ),
  Testimony(
    id: 't3',
    title: 'A new chapter of worship',
    content:
        'Sharing a short clip from last week\'s worship night — such a powerful reminder of what we can do together as a body of believers.',
    author: 'Ama Boateng',
    createdAt: DateTime.now().subtract(const Duration(days: 4)),
    media: const [
      PostMedia(
        networkUrl: 'https://picsum.photos/seed/testify3/700/500',
        isVideo: true,
      ),
    ],
    likes: 18,
    commentCount: 3,
  ),
];

class TestimoniesScreen extends StatefulWidget {
  const TestimoniesScreen({super.key});

  @override
  State<TestimoniesScreen> createState() => _TestimoniesScreenState();
}

class _TestimoniesScreenState extends State<TestimoniesScreen> {
  final List<Testimony> _testimonies = _seedTestimonies();

  Future<void> _openAddTestimony() async {
    final result = await Navigator.push<Testimony>(
      context,
      MaterialPageRoute(builder: (context) => const AddTestimonyScreen()),
    );
    if (result != null) {
      setState(() => _testimonies.insert(0, result));
    }
  }

  void _openDetail(Testimony t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TestimonyDetailScreen(testimony: t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Testimonies & Stories')),
      body: _testimonies.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 64,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No testimonies yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Be the first to share what God has done in your life.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: _testimonies.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Recent Testimonies',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
                final t = _testimonies[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _TestimonyCard(
                    testimony: t,
                    onTap: () => _openDetail(t),
                    onLike: () => setState(() => t.likes++),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTestimony,
        icon: const Icon(Icons.add),
        label: const Text('Share'),
      ),
    );
  }
}

class _TestimonyCard extends StatelessWidget {
  final Testimony testimony;
  final VoidCallback onTap;
  final VoidCallback onLike;
  const _TestimonyCard({
    required this.testimony,
    required this.onTap,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primary.withOpacity(
                      0.12,
                    ),
                    child: testimony.anonymous
                        ? Icon(
                            Icons.visibility_off_outlined,
                            color: theme.colorScheme.primary,
                            size: 18,
                          )
                        : Icon(Icons.person, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          testimony.displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          timeago.format(testimony.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (testimony.media.isNotEmpty)
              _MediaPreview(media: testimony.media),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    testimony.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    testimony.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _ActionChip(
                        icon: Icons.favorite_border,
                        label: '${testimony.likes}',
                        onTap: onLike,
                      ),
                      const SizedBox(width: 8),
                      _ActionChip(
                        icon: Icons.mode_comment_outlined,
                        label: '${testimony.commentCount}',
                        onTap: onTap,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.share_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
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
  }
}

class _MediaPreview extends StatelessWidget {
  final List<PostMedia> media;
  const _MediaPreview({required this.media});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (media.length == 1) {
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: _MediaTile(media: media.first),
      );
    }
    return SizedBox(
      height: 170,
      child: PageView.builder(
        itemCount: media.length,
        controller: PageController(viewportFraction: 0.94),
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: _MediaTile(
              media: media[i],
              indexLabel: '${i + 1}/${media.length}',
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final PostMedia media;
  final String? indexLabel;
  const _MediaTile({required this.media, this.indexLabel});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: media.thumbnailProvider,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade300,
            child: const Icon(Icons.image_not_supported_outlined),
          ),
        ),
        if (media.isVideo)
          Container(
            color: Colors.black26,
            child: const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 46,
              ),
            ),
          ),
        if (indexLabel != null)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                indexLabel!,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TestimonyDetailScreen extends StatefulWidget {
  final Testimony testimony;
  const TestimonyDetailScreen({super.key, required this.testimony});

  @override
  State<TestimonyDetailScreen> createState() => _TestimonyDetailScreenState();
}

class _TestimonyDetailScreenState extends State<TestimonyDetailScreen> {
  final List<Map<String, String>> _comments = [
    {
      'user': 'Efua',
      'text':
          'This really encouraged me in my own situation. Thank you for sharing!',
    },
    {'user': 'Yaw', 'text': 'Praise God! Needed to read this today.'},
  ];
  final _commentController = TextEditingController();

  void _addComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _comments.add({'user': 'You', 'text': text});
      widget.testimony.commentCount++;
      _commentController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.testimony;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (t.media.isNotEmpty)
              SizedBox(
                height: 260,
                child: PageView.builder(
                  itemCount: t.media.length,
                  itemBuilder: (context, i) => _MediaTile(
                    media: t.media[i],
                    indexLabel: t.media.length > 1
                        ? '${i + 1}/${t.media.length}'
                        : null,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primary.withOpacity(
                          0.1,
                        ),
                        child: Icon(
                          Icons.person,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            timeago.format(t.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t.content,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.favorite_border),
                        onPressed: () => setState(() => t.likes++),
                      ),
                      Text('${t.likes}'),
                      const SizedBox(width: 16),
                      const Icon(Icons.comment_outlined),
                      const SizedBox(width: 6),
                      Text('${t.commentCount}'),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Comments (${_comments.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._comments.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: theme.colorScheme.primary
                                .withOpacity(0.1),
                            child: Icon(
                              Icons.person,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c['user']!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(c['text']!),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentController,
                    onSubmitted: (_) => _addComment(),
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _addComment,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddTestimonyScreen extends StatefulWidget {
  const AddTestimonyScreen({super.key});

  @override
  State<AddTestimonyScreen> createState() => _AddTestimonyScreenState();
}

class _AddTestimonyScreenState extends State<AddTestimonyScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _picker = ImagePicker();
  final List<PostMedia> _media = [];
  bool _anonymous = false;
  bool _posting = false;

  static const int _maxMedia = 6;

  Future<void> _pickFromGallery() async {
    if (_media.length >= _maxMedia) return _showLimitReached();
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() {
      for (final p in picked) {
        if (_media.length >= _maxMedia) break;
        _media.add(PostMedia(file: File(p.path)));
      }
    });
  }

  Future<void> _takePhoto() async {
    if (_media.length >= _maxMedia) return _showLimitReached();
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _media.add(PostMedia(file: File(picked.path))));
  }

  Future<void> _pickVideo() async {
    if (_media.length >= _maxMedia) return _showLimitReached();
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    setState(
      () => _media.add(PostMedia(file: File(picked.path), isVideo: true)),
    );
  }

  void _showLimitReached() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You can attach up to $_maxMedia files per post'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openMediaSheet() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photos from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Attach a video'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _removeMedia(int index) => setState(() => _media.removeAt(index));

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a title and share your story'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _posting = true);
    // TODO: replace with a real call to the posts/testimonies repository,
    // uploading each PostMedia file before saving the record.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final testimony = Testimony(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      content: content,
      author: 'You',
      anonymous: _anonymous,
      media: List.of(_media),
    );
    Navigator.pop(context, testimony);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Share Your Testimony')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your story can inspire others',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Your Testimony',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Photos & video (optional)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add up to $_maxMedia files to bring your story to life',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ..._media.asMap().entries.map((entry) {
                    final i = entry.key;
                    final m = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 96,
                              height: 96,
                              color: theme.colorScheme.surfaceVariant,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image(
                                    image: m.thumbnailProvider,
                                    fit: BoxFit.cover,
                                  ),
                                  if (m.isVideo)
                                    const Center(
                                      child: Icon(
                                        Icons.play_circle_fill,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => _removeMedia(i),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_media.length < _maxMedia)
                    InkWell(
                      onTap: _openMediaSheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_outlined,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 4),
                            Text('Add', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(child: Text('Share anonymously')),
                  Switch(
                    value: _anonymous,
                    onChanged: (v) => setState(() => _anonymous = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _posting ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _posting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Share Testimony'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
