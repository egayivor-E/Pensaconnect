import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../repositories/testimony_repository.dart';

class AddTestimonyScreen extends StatefulWidget {
  const AddTestimonyScreen({super.key});

  @override
  State<AddTestimonyScreen> createState() => _AddTestimonyScreenState();
}

class _AddTestimonyScreenState extends State<AddTestimonyScreen> {
  final _repo = TestimonyRepository();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _anonymous = false;
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final testimonyData = {
      "title": _titleController.text.trim(),
      "content": _contentController.text.trim(),
      "is_anonymous": _anonymous,
    };

    debugPrint('📤 Sending testimony data: $testimonyData');

    try {
      await _repo.addTestimony(testimonyData);
      debugPrint('✅ Testimony submitted successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Testimony shared successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // ✅ FIXED: Simple pop without parameters
        context.pop();
      }
    } catch (e) {
      debugPrint('❌ Error submitting testimony: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share testimony: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String? _validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a title';
    }
    if (value.trim().length < 3) {
      return 'Title must be at least 3 characters long';
    }
    return null;
  }

  String? _validateContent(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please share your testimony';
    }
    if (value.trim().length < 10) {
      return 'Testimony must be at least 10 characters long';
    }
    return null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Your Testimony'),
        // ✅ FIXED: Simplified back navigation
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Share Your Story',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your testimony can inspire and encourage others in their faith journey.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'Give your testimony a meaningful title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: _validateTitle,
                maxLength: 100,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _contentController,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Your Testimony *',
                  hintText: 'Share your story, experience, or encouragement...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: _validateContent,
                maxLength: 2000,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 16),
              Text(
                '${_contentController.text.trim().length}/2000 characters',
                style: TextStyle(
                  fontSize: 12,
                  color: _contentController.text.trim().length > 2000
                      ? Colors.red
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_off, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Share anonymously',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Your name will not be displayed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _anonymous,
                        onChanged: _loading
                            ? null
                            : (val) => setState(() => _anonymous = val),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Share Testimony',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              if (!_loading)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => context.pop(), // ✅ FIXED: Simplified
                    child: const Text('Cancel'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
