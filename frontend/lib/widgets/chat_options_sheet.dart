import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ChatOptionsSheet extends StatelessWidget {
  const ChatOptionsSheet({super.key});

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
            onTap: () {
              Navigator.pop(context);
              context.push("/messages/new");
            },
          ),
          ListTile(
            leading: const Icon(Icons.group, color: Colors.blue),
            title: const Text("Group Chats"),
            subtitle: const Text("Join and chat with your group"),
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
