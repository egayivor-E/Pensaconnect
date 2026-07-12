// lib/screens/new_message_screen.dart
//
// User picker for starting a direct message. Tapping a user calls the
// get-or-create direct-chat endpoint and lands in the same detail screen
// group chats use — a DM is just a 2-member GroupChat under the hood, so
// there's nothing DM-specific about the messaging UI itself.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../repositories/user_repository.dart';
import '../repositories/group_chat_repository.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final _userRepo = UserRepository();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _errorMessage;
  List<User> _users = [];
  String _query = '';
  // The single user currently being started as a DM — disables the whole
  // list rather than just one row, since tapping a second name mid-request
  // would fire a second get-or-create call before the first resolves.
  int? _startingChatWith;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final currentUserId = AuthService().userId;
      final users = await _userRepo.listUsers();
      if (!mounted) return;
      setState(() {
        _users = users.where((u) => u.id != currentUserId).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _startChat(User user) async {
    setState(() => _startingChatWith = user.id);
    try {
      final chat = await context
          .read<GroupChatRepository>()
          .getOrCreateDirectChat(user.id);
      if (!mounted) return;
      context.replace(
        '/group-chats/detail',
        extra: {'groupId': chat.id, 'groupName': user.getFullName()},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't start a chat with ${user.getFullName()}."),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _startingChatWith = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _query.isEmpty
        ? _users
        : _users
            .where((u) => u.getFullName().toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: const Text('New Message')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search people',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: theme.colorScheme.onSurface.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildBody(theme, filtered)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, List<User> filtered) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            const Text("Couldn't load people"),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No one to message yet' : 'No matches for "$_query"',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      );
    }

    final busy = _startingChatWith != null;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final user = filtered[index];
        final isThisOneStarting = _startingChatWith == user.id;

        return ListTile(
          enabled: !busy,
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: (user.profilePicture != null && user.profilePicture!.isNotEmpty)
                ? NetworkImage(user.getProfilePictureUrl(ApiService.baseUrl))
                : null,
            child: (user.profilePicture == null || user.profilePicture!.isEmpty)
                ? Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer)
                : null,
          ),
          title: Text(user.getFullName()),
          trailing: isThisOneStarting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: busy ? null : () => _startChat(user),
        );
      },
    );
  }
}
