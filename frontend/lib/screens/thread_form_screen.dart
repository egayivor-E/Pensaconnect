import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/threads_provider.dart';

class ThreadFormScreen extends StatefulWidget {
  const ThreadFormScreen({super.key});

  @override
  State<ThreadFormScreen> createState() => _ThreadFormScreenState();
}

class _ThreadFormScreenState extends State<ThreadFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final provider = context.read<ThreadsProvider>();
    await provider.addThread(_titleController.text, _descController.text);

    if (mounted) {
      context.pop(true); // ✅ tells previous screen a thread was created
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Thread")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: "Title"),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter thread title" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: "Description"),
                maxLines: 3,
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter description" : null,
              ),
              const SizedBox(height: 20),
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _submit,
                      child: const Text("Create Thread"),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
