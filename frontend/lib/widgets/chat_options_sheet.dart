import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../repositories/group_chat_repository.dart';

class ChatOptionsSheet extends StatefulWidget {
  const ChatOptionsSheet({super.key});

  @override
  State<ChatOptionsSheet> createState() => _ChatOptionsSheetState();
}

class _ChatOptionsSheetState extends State<ChatOptionsSheet> {
  // Split unread counts (group vs. direct), fetched once when the sheet
  // opens. Null while loading — kept separate from 0 so a badge doesn't
  // flash in at 0 and immediately disappear before the real count arrives.
  int? _groupUnread;
  int? _directUnread;

  @override
  void initState() {
    super.initState();
    _loadUnreadCounts();
  }

  Future<void> _loadUnreadCounts() async {
    final counts = await context
        .read<GroupChatRepository>()
        .fetchUnreadCountsByType();
    if (!mounted) return;
    setState(() {
      _groupUnread = counts.groupCount;
      _directUnread = counts.directCount;
    });
  }

  Widget? _badge(int? count) {
    if (count == null || count <= 0) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onError,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.green),
            title: const Text("New Message"),
            subtitle: const Text("Send a direct message to someone"),
            trailing: _badge(_directUnread),
            onTap: () {
              Navigator.pop(context);
              context.push("/messages/new");
            },
          ),
          ListTile(
            leading: const Icon(Icons.group, color: Colors.blue),
            title: const Text("Group Chats"),
            subtitle: const Text("Join and chat with your group"),
            trailing: _badge(_groupUnread),
            onTap: () {
              Navigator.pop(context);
              context.go("/group-chats");
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock, color: Colors.red),
            title: const Text("Anonymous Message"),
            subtitle: const Text("Send a message to leaders/admins"),
            onTap: () {
              Navigator.pop(context);
              context.go("/anonymous-chat");
            },
          ),
        ],
      ),
    );
  }
}
