// lib/screens/discover_groups_screen.dart
//
// Browse public groups the current user hasn't joined yet, and join them
// directly from here. This is the missing other half of "Group Chats":
// GroupChatsScreen only ever lists groups you're already a member of —
// there was previously no way to discover or join a new one at all.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/group_chat_model.dart';
import '../repositories/group_chat_repository.dart';

class DiscoverGroupsScreen extends StatefulWidget {
  const DiscoverGroupsScreen({super.key});

  @override
  State<DiscoverGroupsScreen> createState() => _DiscoverGroupsScreenState();
}

class _DiscoverGroupsScreenState extends State<DiscoverGroupsScreen> {
  bool _loading = true;
  List<GroupChat> _groups = [];
  String? _errorMessage;
  // Tracks in-flight joins per group id so the tile can show a spinner
  // and can't be double-tapped while the request is still out.
  final Set<int> _joining = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final groups = await context.read<GroupChatRepository>().discoverGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
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

  Future<void> _join(GroupChat group) async {
    setState(() => _joining.add(group.id));
    try {
      await context.read<GroupChatRepository>().joinGroup(group.id);
      if (!mounted) return;
      // Joined — it no longer belongs in "discover", and the group
      // detail screen (reached the same way GroupChatsScreen reaches it)
      // is the natural next stop.
      setState(() => _groups.removeWhere((g) => g.id == group.id));
      context.push(
        '/group-chats/detail',
        extra: {'groupId': group.id, 'groupName': group.name},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not join "${group.name}": ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _joining.remove(group.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: const Text('Discover Groups')),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                "Couldn't load groups",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.explore_off_rounded,
                size: 40,
                color: theme.colorScheme.onSurface.withOpacity(0.35),
              ),
              const SizedBox(height: 12),
              Text(
                "No new groups to join right now",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "You're already in every public group, or none exist yet.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemCount: _groups.length,
        itemBuilder: (context, index) => _buildTile(theme, _groups[index]),
      ),
    );
  }

  Widget _buildTile(ThemeData theme, GroupChat group) {
    final colorScheme = theme.colorScheme;
    final isJoining = _joining.contains(group.id);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.groups_rounded,
                color: colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    group.description.isNotEmpty
                        ? group.description
                        : '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 34,
              child: isJoining
                  ? const SizedBox(
                      width: 34,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : OutlinedButton(
                      onPressed: () => _join(group),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Join'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
