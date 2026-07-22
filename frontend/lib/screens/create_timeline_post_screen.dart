// screens/create_timeline_post_screen.dart
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/timeline_post_model.dart';
import '../repositories/timeline_post_repository.dart';

class CreateTimelinePostScreen extends StatefulWidget {
  const CreateTimelinePostScreen({super.key});

  @override
  State<CreateTimelinePostScreen> createState() =>
      _CreateTimelinePostScreenState();
}

class _CreateTimelinePostScreenState extends State<CreateTimelinePostScreen> {
  final _repo = TimelinePostRepository();
  final _picker = ImagePicker();
  final _contentController = TextEditingController();

  XFile? _mediaFile;
  bool _mediaIsVideo = false;
  bool _posting = false;
  // Distinguishes "uploading the attached photo/video" from "creating
  // the post" so the button label reflects which (slower) step is
  // actually in progress, instead of a single generic spinner that
  // looks the same whether it's been 1 second or 30.
  String? _postingLabel;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    // Capped size/quality so a phone photo (often 3-4k px, several MB)
    // doesn't turn "attach a photo" into a multi-minute upload. 1280px
    // and quality 70 is still sharp on any phone/tablet screen.
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (picked == null) return;
    setState(() {
      _mediaFile = picked;
      _mediaIsVideo = false;
    });
  }

  Future<void> _pickVideo() async {
    // Capped to 60 seconds so someone can't accidentally attach a huge
    // clip that then sits uploading for minutes with no way to tell
    // it's still working.
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (picked == null) return;
    setState(() {
      _mediaFile = picked;
      _mediaIsVideo = true;
    });
  }

  void _removeMedia() => setState(() => _mediaFile = null);

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
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Attach a video (max 60s)'),
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

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write something to share first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _posting = true;
      _postingLabel = _mediaFile != null ? 'Uploading...' : 'Posting...';
    });
    try {
      String? imageUrl;
      bool isVideo = false;

      if (_mediaFile != null) {
        final uploaded = await _repo.uploadMedia(_mediaFile!);
        imageUrl = uploaded.url;
        isVideo = uploaded.isVideo;
        if (mounted) setState(() => _postingLabel = 'Posting...');
      }

      final post = await _repo.addPost(
        content: content,
        imageUrl: imageUrl,
        isVideo: isVideo,
      );

      if (!mounted) return;
      Navigator.pop(context, post);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to share post: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _posting = false;
          _postingLabel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Post'),
        actions: [
          TextButton(
            onPressed: _posting ? null : _submit,
            child: _posting
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(_postingLabel ?? 'Posting...'),
                    ],
                  )
                : const Text('Share'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _contentController,
              maxLines: 6,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "What's on your heart today?",
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 12),
            if (_mediaFile != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: _mediaIsVideo
                          ? Container(
                              color: Colors.black87,
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 56,
                                ),
                              ),
                            )
                          : (kIsWeb
                                ? Image.network(
                                    _mediaFile!.path,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    File(_mediaFile!.path),
                                    fit: BoxFit.cover,
                                  )),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _posting ? null : _removeMedia,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: _posting ? null : _openMediaSheet,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add a photo or video'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}