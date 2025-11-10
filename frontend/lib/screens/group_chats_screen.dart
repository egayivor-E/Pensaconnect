// lib/screens/group_chats_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart'; // Add this import

import '../models/group_chat_model.dart';
import '../repositories/group_chat_repository.dart';

class GroupChatsScreen extends StatefulWidget {
  const GroupChatsScreen({super.key});

  @override
  State<GroupChatsScreen> createState() => _GroupChatsScreenState();
}

class _GroupChatsScreenState extends State<GroupChatsScreen> {
  bool _loading = true;
  List<GroupChat> _groups = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // ✅ FIXED: Get GroupChatRepository from Provider instead of creating new instance
      final groupRepo = context.read<GroupChatRepository>();
      final groups = await groupRepo.getGroups();

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading groups: $e');
      if (!mounted) return;
      setState(() {
        _groups = [];
        _loading = false;
        _errorMessage = e.toString();
      });

      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load groups: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Chats'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadGroups),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Failed to load groups',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loadGroups,
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            )
          : _groups.isEmpty
          ? const Center(child: Text("No groups available"))
          : ListView.builder(
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final group = _groups[index];
                return ListTile(
                  leading: const Icon(Icons.group),
                  title: Text(group.name),
                  subtitle: Text(group.description),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push(
                      '/group-chats/detail', // ✅ Match the route path (plural "chats")
                      extra: {
                        'groupId': group.id is String
                            ? int.tryParse(group.id as String) ?? 0
                            : group.id,
                        'groupName': group.name,
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
