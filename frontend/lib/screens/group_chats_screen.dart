// lib/screens/group_chats_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/group_chat_model.dart';
import '../repositories/group_chat_repository.dart';
import '../services/socketio_service.dart'; // ✅ ADDED

class GroupChatsScreen extends StatefulWidget {
  const GroupChatsScreen({super.key});

  @override
  State<GroupChatsScreen> createState() => _GroupChatsScreenState();
}

class _GroupChatsScreenState extends State<GroupChatsScreen> {
  bool _loading = true;
  List<GroupChat> _groups = [];
  String? _errorMessage;
  bool _initialLoadDone = false; // ✅ ADDED: Track initial load

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    // ✅ Prevent duplicate loads
    if (_initialLoadDone && _groups.isNotEmpty) {
      debugPrint('📦 Groups already loaded, skipping...');
      return;
    }

    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // ✅ Get GroupChatRepository from Provider
      final groupRepo = context.read<GroupChatRepository>();
      final groups = await groupRepo.getGroups();

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
        _initialLoadDone = true;
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
          behavior: SnackBarBehavior.floating,
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // ✅ Reset flag to allow refresh
              _initialLoadDone = false;
              _loadGroups();
            },
            tooltip: 'Refresh groups',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load groups',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No groups available',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Join or create a group to get started',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _groups.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final group = _groups[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.group,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      group.description.isNotEmpty
                          ? group.description
                          : 'No description',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (group.memberCount != null)
                          Row(
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${group.memberCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                    onTap: () {
                      context.push(
                        '/group-chats/detail',
                        extra: {
                          'groupId': group.id is String
                              ? int.tryParse(group.id as String) ?? 0
                              : group.id,
                          'groupName': group.name,
                        },
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    // ✅ No socket cleanup needed here since we're not connected to a specific group
    super.dispose();
  }
}
