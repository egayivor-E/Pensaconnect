import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../repositories/forum_repository.dart';

class PostFormScreen extends StatefulWidget {
  final int threadId;
  final String threadTitle;

  const PostFormScreen({
    super.key,
    required this.threadId,
    required this.threadTitle,
  });

  @override
  State<PostFormScreen> createState() => _PostFormScreenState();
}

class _PostFormScreenState extends State<PostFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentCtrl = TextEditingController();

  List<PlatformFile> _attachments = [];
  final _repo = ForumRepository();
  bool _isLoading = false;

  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp'};
  static const _videoExtensions = {'mp4', 'mov', 'avi', 'webm', 'mkv', 'm4v'};

  bool _isImage(PlatformFile f) =>
      _imageExtensions.contains((f.extension ?? '').toLowerCase());
  bool _isVideo(PlatformFile f) =>
      _videoExtensions.contains((f.extension ?? '').toLowerCase());

  Future<void> _pickFiles() async {
    // Photos/videos/docs — matches the backend's ALLOWED_EXTENSIONS in
    // forums.py, so nothing picked here gets silently rejected server-side.
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        ..._imageExtensions,
        ..._videoExtensions,
        'pdf', 'docx', 'txt',
      ],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _attachments = [..._attachments, ...result.files];
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final success = await _repo.createPost(
        threadId: widget.threadId,
        title: widget.threadTitle,
        content: _contentCtrl.text,
        attachments: _attachments,
      );

      if (mounted) context.pop(success);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Submission failed: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Post")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _contentCtrl,
                decoration: const InputDecoration(
                  labelText: "Write something...",
                ),
                maxLines: 5,
                validator: (val) =>
                    val == null || val.isEmpty ? "Content required" : null,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickFiles,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text("Add photos, videos, or files"),
              ),
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    "${_attachments.length} file(s) attached",
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              Expanded(
                child: ListView(
                  children: _attachments
                      .map(
                        (file) => ListTile(
                          leading: _isImage(file) && file.path != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    File(file.path!),
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  _isVideo(file)
                                      ? Icons.videocam_outlined
                                      : Icons.insert_drive_file,
                                ),
                          title: Text(file.name),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _attachments.remove(file)),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text("Submit Post"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
