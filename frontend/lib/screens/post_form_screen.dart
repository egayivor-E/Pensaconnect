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

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _attachments = result.files.toList();
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final success = await _repo.createPost(
        threadId: widget.threadId,
        title: "threadTitle", // ✅ still pass empty string if backend expects it
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
                icon: const Icon(Icons.attach_file),
                label: const Text("Add attachments"),
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
                          leading: const Icon(Icons.insert_drive_file),
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
