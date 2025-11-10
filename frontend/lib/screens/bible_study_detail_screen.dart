// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, depend_on_referenced_packages, unnecessary_null_comparison

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pensaconnect/models/bible_models.dart';

class BibleStudyDetailScreen extends StatefulWidget {
  final Object item;
  final bool isUserCreated;
  const BibleStudyDetailScreen({
    super.key,
    required this.item,
    this.isUserCreated = false,
  });

  @override
  State<BibleStudyDetailScreen> createState() => _BibleStudyDetailScreenState();
}

class _BibleStudyDetailScreenState extends State<BibleStudyDetailScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  final TextEditingController _noteController = TextEditingController();

  // User interaction state
  bool _isBookmarked = false;
  bool _isLiked = false;
  int _likeCount = 0;
  double _completionPercentage = 0.0;
  List<String> _userNotes = [];
  bool _editing = false;
  bool _showNoteInput = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    // Simulate loading user data
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isBookmarked = false;
          _isLiked = false;
          _likeCount = 15; // Example data
          _completionPercentage = 0.3;
          _userNotes = [
            'This really spoke to me today!',
            'Need to study this verse more deeply',
          ];
        });
      }
    });
  }

  void _startEditing() {
    setState(() => _editing = true);
  }

  void _saveChanges() {
    setState(() => _editing = false);
    _showSnackBar('Changes saved successfully');
  }

  void _addPersonalNote() {
    if (_noteController.text.trim().isNotEmpty) {
      setState(() {
        _userNotes.add(_noteController.text);
        _noteController.clear();
        _showNoteInput = false;
      });
      _showSnackBar('Note added');
    }
  }

  void _toggleBookmark() {
    setState(() => _isBookmarked = !_isBookmarked);
    _showSnackBar(
      _isBookmarked ? 'Added to bookmarks' : 'Removed from bookmarks',
    );
  }

  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });
  }

  void _updateProgress(double progress) {
    setState(() => _completionPercentage = progress);
    _showSnackBar('Progress updated to ${(progress * 100).toInt()}%');
  }

  void _archiveItem() {
    _showSnackBar('Added to your archive');
  }

  void _toggleNoteInput() {
    setState(() => _showNoteInput = !_showNoteInput);
  }

  Future<void> _shareScreenshot(
    BuildContext context,
    Widget body,
    String title,
  ) async {
    try {
      final theme = Theme.of(context);

      final imageBytes = await _screenshotController.captureFromWidget(
        Directionality(
          textDirection: Directionality.of(context),
          child: MediaQuery(
            data: MediaQuery.of(context),
            child: Theme(
              data: theme,
              child: Scaffold(
                backgroundColor: Colors.white,
                body: Stack(
                  children: [
                    body,
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Opacity(
                        opacity: 0.75,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _OptionalLogo(
                              color: theme.colorScheme.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "PensaConnect",
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      if (imageBytes == null) return;

      if (kIsWeb) {
        await Share.shareXFiles([
          XFile.fromData(
            imageBytes,
            mimeType: 'image/png',
            name: 'bible_study.png',
          ),
        ], text: "📖 $title - Shared via PensaConnect");
      } else {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/bible_study.png');
        await file.writeAsBytes(imageBytes);

        await Share.shareXFiles([
          XFile(file.path),
        ], text: "📖 $title - Shared via PensaConnect");
      }
    } catch (e) {
      debugPrint("Error capturing screenshot: $e");
      _showSnackBar("Failed to share: ${e.toString()}");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getTitle(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.isUserCreated)
              Text(
                'My Creation',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        actions: _buildAppBarActions(theme),
      ),
      body: _buildBody(theme),
      floatingActionButton: _buildFAB(),
    );
  }

  List<Widget> _buildAppBarActions(ThemeData theme) {
    return [
      // Progress indicator
      if (_completionPercentage > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${(_completionPercentage * 100).toInt()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                'Complete',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),

      // Bookmark
      IconButton(
        icon: Icon(
          _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
          color: _isBookmarked ? theme.colorScheme.primary : null,
        ),
        onPressed: _toggleBookmark,
        tooltip: _isBookmarked ? 'Remove bookmark' : 'Add bookmark',
      ),

      // Like with counter
      Stack(
        children: [
          IconButton(
            icon: Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border,
              color: _isLiked ? Colors.red : null,
            ),
            onPressed: _toggleLike,
            tooltip: 'Like',
          ),
          if (_likeCount > 0)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  _likeCount > 99 ? '99+' : '$_likeCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),

      // Share
      IconButton(
        icon: const Icon(Icons.share),
        onPressed: () =>
            _shareScreenshot(context, _buildContent(theme), _getTitle()),
        tooltip: 'Share',
      ),

      // Edit button for user-created content
      if (widget.isUserCreated)
        IconButton(
          icon: Icon(_editing ? Icons.save : Icons.edit),
          onPressed: _editing ? _saveChanges : _startEditing,
          tooltip: _editing ? 'Save changes' : 'Edit',
        ),
    ];
  }

  Widget _buildBody(ThemeData theme) {
    return Stack(
      children: [
        Screenshot(
          controller: _screenshotController,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Main content
              _buildContent(theme),

              // User Notes Section
              if (_userNotes.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildUserNotesSection(theme),
              ],

              // Note Input Section
              const SizedBox(height: 24),
              _buildNoteInputSection(theme),

              // Progress Section
              const SizedBox(height: 24),
              _buildProgressSection(theme),

              // Extra spacing for FAB
              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserNotesSection(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('My Notes', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: _toggleNoteInput,
                  tooltip: 'Add note',
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._userNotes.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.arrow_right,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.value, style: theme.textTheme.bodyMedium),
                          if (entry.key != _userNotes.length - 1)
                            const Divider(height: 16),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        setState(() => _userNotes.removeAt(entry.key));
                      },
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

  Widget _buildNoteInputSection(ThemeData theme) {
    if (!_showNoteInput) {
      return Center(
        child: FilledButton.tonal(
          onPressed: _toggleNoteInput,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.note_add),
              SizedBox(width: 8),
              Text('Add Personal Note'),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.note_add,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Add Personal Note', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _toggleNoteInput,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Write your thoughts, reflections, or insights...',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: _addPersonalNote,
                  child: const Text('Save Note'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timeline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Reading Progress', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _completionPercentage,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(_completionPercentage * 100).toInt()}% Complete',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _updateProgress(0.25),
                      child: const Text('25%'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _updateProgress(0.50),
                      child: const Text('50%'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _updateProgress(1.0),
                      child: const Text('Complete'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: () => _shareScreenshot(
        context,
        _buildContent(Theme.of(context)),
        _getTitle(),
      ),
      child: const Icon(Icons.share),
    );
  }

  String _getTitle() {
    if (widget.item is Devotion) return (widget.item as Devotion).verse;
    if (widget.item is StudyPlan) return (widget.item as StudyPlan).title;
    if (widget.item is ArchiveItem) return (widget.item as ArchiveItem).title;
    return 'Bible Study';
  }

  Widget _buildContent(ThemeData theme) {
    if (widget.item is Devotion)
      return _buildDevotionContent(widget.item as Devotion, theme);
    if (widget.item is StudyPlan)
      return _buildStudyPlanContent(widget.item as StudyPlan, theme);
    if (widget.item is ArchiveItem)
      return _buildArchiveContent(widget.item as ArchiveItem, theme);
    return const Center(child: Text('Unknown content type'));
  }

  // COMPLETE CONTENT BUILDING METHODS
  Widget _buildDevotionContent(Devotion d, ThemeData theme) {
    return Column(
      children: [
        _buildHeroSection(
          title: d.verse,
          subtitle: 'Daily Devotion',
          icon: Icons.book,
          theme: theme,
        ),
        const SizedBox(height: 24),
        _buildContentSection(
          title: 'Devotional Content',
          content: d.content,
          icon: Icons.lightbulb_outline,
          theme: theme,
        ),
        if (d.reflection != null && d.reflection!.trim().isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildContentSection(
            title: 'Personal Reflection',
            content: d.reflection!,
            icon: Icons.psychology_outlined,
            theme: theme,
          ),
        ],
        if (d.prayer != null && d.prayer!.trim().isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildContentSection(
            title: 'Prayer',
            content: d.prayer!,
            icon: Icons.self_improvement,
            theme: theme,
          ),
        ],
        if (d.date != null) ...[
          const SizedBox(height: 20),
          _buildInfoSection(
            title: 'Date',
            content: _formatDate(d.date!),
            icon: Icons.calendar_today,
            theme: theme,
          ),
        ],
      ],
    );
  }

  Widget _buildStudyPlanContent(StudyPlan p, ThemeData theme) {
    return Column(
      children: [
        _buildHeroSection(
          title: p.title,
          subtitle: 'Study Plan',
          icon: Icons.school,
          theme: theme,
        ),
        const SizedBox(height: 24),
        _buildContentSection(
          title: 'Description',
          content: p.description,
          icon: Icons.description_outlined,
          theme: theme,
        ),
        if (p.verses.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildVersesSection(p.verses, theme),
        ],
        if (p.dayCount != null) ...[
          const SizedBox(height: 20),
          _buildInfoSection(
            title: 'Duration',
            content: '${p.dayCount} days',
            icon: Icons.schedule,
            theme: theme,
          ),
        ],
      ],
    );
  }

  Widget _buildArchiveContent(ArchiveItem a, ThemeData theme) {
    return Column(
      children: [
        _buildHeroSection(
          title: a.title,
          subtitle: 'Archive Item',
          icon: Icons.archive_outlined,
          theme: theme,
        ),
        const SizedBox(height: 24),
        _buildContentSection(
          title: 'Description',
          content: a.description,
          icon: Icons.description_outlined,
          theme: theme,
        ),
        const SizedBox(height: 20),
        _buildInfoSection(
          title: 'Date Archived',
          content: _formatDate(a.date),
          icon: Icons.calendar_today,
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildHeroSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withOpacity(0.1),
              theme.colorScheme.secondary.withOpacity(0.05),
            ],
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSection({
    required String title,
    required String content,
    required IconData icon,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurface.withOpacity(0.9),
              ),
              textAlign: TextAlign.justify,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersesSection(List<String> verses, ThemeData theme) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_stories,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Bible Verses',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...verses.map(
              (verse) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        verse,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
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

  Widget _buildInfoSection({
    required String title,
    required String content,
    required IconData icon,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _OptionalLogo extends StatelessWidget {
  final Color color;
  final double size;
  const _OptionalLogo({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _assetExists(context, "assets/logo.png"),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data == true) {
          return Image.asset(
            "assets/logo.png",
            width: size,
            height: size,
            color: color,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Future<bool> _assetExists(BuildContext context, String path) async {
    try {
      final bundle = DefaultAssetBundle.of(context);
      final data = await bundle.load(path);
      return data.lengthInBytes > 0;
    } catch (_) {
      return false;
    }
  }
}
