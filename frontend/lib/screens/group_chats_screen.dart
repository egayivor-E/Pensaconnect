// lib/screens/group_chats_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/group_chat_model.dart';
import '../repositories/group_chat_repository.dart';

class GroupChatsScreen extends StatefulWidget {
  const GroupChatsScreen({super.key});

  @override
  State<GroupChatsScreen> createState() => _GroupChatsScreenState();
}

class _GroupChatsScreenState extends State<GroupChatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  List<GroupChat> _groups = [];
  String? _errorMessage;
  bool _initialLoadDone = false;

  // Instant Chats (chat_type='direct') get their own independent
  // loading/error/data state rather than reusing the group chat fields
  // above — the two lists are fetched separately (see _loadChats) and a
  // failure/refresh in one tab must not affect the other.
  bool _directLoading = true;
  List<GroupChat> _directChats = [];
  String? _directErrorMessage;
  bool _directInitialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadGroups();
    _loadDirectChats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups({bool force = false}) async {
    if (!force && _initialLoadDone && _groups.isNotEmpty) {
      debugPrint('📦 Groups already loaded, skipping...');
      return;
    }

    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final groupRepo = context.read<GroupChatRepository>();
      // This tab is "Groups" specifically — 1:1 Instant Chats
      // (chat_type='direct') are a different concept with their own tab
      // below and shouldn't show up mixed in here as unlabeled dm-x-y
      // rows indistinguishable from real, intentionally-created groups
      // like "THE BLUEPRINT".
      final groups = await groupRepo.getGroups(type: 'group');

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load groups: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _loadDirectChats({bool force = false}) async {
    if (!force && _directInitialLoadDone && _directChats.isNotEmpty) {
      debugPrint('📦 Instant chats already loaded, skipping...');
      return;
    }

    if (!mounted) return;

    setState(() {
      _directLoading = true;
      _directErrorMessage = null;
    });

    try {
      final groupRepo = context.read<GroupChatRepository>();
      final chats = await groupRepo.getGroups(type: 'direct');

      if (!mounted) return;
      setState(() {
        _directChats = chats;
        _directLoading = false;
        _directInitialLoadDone = true;
      });
    } catch (e) {
      debugPrint('❌ Error loading instant chats: $e');
      if (!mounted) return;
      setState(() {
        _directChats = [];
        _directLoading = false;
        _directErrorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load chats: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  // ✅ FIX: centralized "go home" navigation used by both the AppBar back
  // arrow and the hardware/system back gesture below. Using context.go()
  // instead of context.pop() means we always land on a known route rather
  // than popping into a stale or circular entry in the navigation stack
  // (the cause of the "looping" back behavior).
  void _goHome() {
    context.go('/home');
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      _goHome();
    }
  }

  Future<void> _openDiscover() async {
    await context.push('/group-chats/discover');
    // A join on the discover screen adds a group this screen doesn't know
    // about yet — refresh on return so it shows up without a manual pull.
    if (mounted) _loadGroups(force: true);
  }

  Future<void> _createGroup() async {
    final result = await showDialog<_CreateGroupResult>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (result == null || !mounted) return;

    try {
      final groupRepo = context.read<GroupChatRepository>();
      final group = await groupRepo.createGroup(
        name: result.name,
        description: result.description,
        isPublic: result.isPublic,
      );
      if (!mounted) return;
      _loadGroups(force: true);
      context.push(
        '/group-chats/detail',
        extra: {'groupId': group.id, 'groupName': group.name},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create group: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openNewMessage() async {
    await context.push('/messages/new');
    // Starting (or reopening) a chat there adds/updates a row this tab
    // doesn't know about yet — refresh on return, same reasoning as
    // _openChat below.
    if (mounted) _loadDirectChats(force: true);
  }

  /// Opens a specific chat/group, then refreshes *that tab's* list on
  /// return. Reading the conversation marks it read server-side (see
  /// GroupChatDetailScreen._initialize()'s markGroupRead call), so
  /// without this refresh the tile you just read would keep showing its
  /// old unread badge until the next manual pull-to-refresh — the exact
  /// chat you opened wouldn't reflect that it'd been read.
  Future<void> _openChat(GroupChat chat) async {
    await context.push(
      '/group-chats/detail',
      extra: {'groupId': chat.id, 'groupName': chat.displayName},
    );
    if (!mounted) return;
    if (chat.isDirect) {
      _loadDirectChats(force: true);
    } else {
      _loadGroups(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ✅ FIX: PopScope intercepts the Android hardware/gesture back button.
    // Previously, with no explicit handling, back-navigation could bounce
    // between routes that kept re-pushing each other (a redirect loop) if
    // this screen had no meaningful parent in the stack. Now, if there's
    // nothing left to pop, we deliberately go home instead of letting the
    // router fall back to default (looping) behavior.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          title: const Text('Chats'),
          actions: [
            IconButton(
              icon: const Icon(Icons.explore_outlined),
              onPressed: _openDiscover,
              tooltip: 'Discover groups',
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _tabController.index == 0
                  ? _loadGroups(force: true)
                  : _loadDirectChats(force: true),
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                child: _buildTabLabel(
                  'Groups',
                  _groups.fold<int>(0, (sum, g) => sum + g.unreadCount),
                ),
              ),
              Tab(
                child: _buildTabLabel(
                  'Instant Chats',
                  _directChats.fold<int>(0, (sum, c) => sum + c.unreadCount),
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildBody(
              theme,
              loading: _loading,
              errorMessage: _errorMessage,
              chats: _groups,
              onRefresh: () => _loadGroups(force: true),
              emptyState: _buildEmptyState(theme),
            ),
            _buildBody(
              theme,
              loading: _directLoading,
              errorMessage: _directErrorMessage,
              chats: _directChats,
              onRefresh: () => _loadDirectChats(force: true),
              emptyState: _buildDirectEmptyState(theme),
            ),
          ],
        ),
        floatingActionButton: AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) => _tabController.index == 0
              ? FloatingActionButton.extended(
                  onPressed: _createGroup,
                  icon: const Icon(Icons.add),
                  label: const Text('Create group'),
                )
              : FloatingActionButton.extended(
                  onPressed: _openNewMessage,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('New message'),
                ),
        ),
      ),
    );
  }

  Widget _buildTabLabel(String label, int unreadCount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (unreadCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            constraints: const BoxConstraints(minWidth: 18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unreadCount > 99 ? '99+' : '$unreadCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onError,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBody(
    ThemeData theme, {
    required bool loading,
    required String? errorMessage,
    required List<GroupChat> chats,
    required Future<void> Function() onRefresh,
    required Widget emptyState,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return _buildErrorState(theme, errorMessage, onRefresh);
    }

    if (chats.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: 480, child: emptyState)],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: chats.length,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemBuilder: (context, index) => _buildGroupTile(theme, chats[index]),
      ),
    );
  }

  Widget _buildGroupTile(ThemeData theme, GroupChat group) {
    final colorScheme = theme.colorScheme;
    final displayName = group.displayName;
    final avatarColor = _colorForName(displayName, colorScheme);
    final avatarUrl = group.displayAvatar;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openChat(group),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: avatarColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                  image: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? null
                    : Center(
                        child: Text(
                          _initialsForGroup(displayName),
                          style: TextStyle(
                            color: avatarColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      group.isDirect
                          ? 'Tap to view conversation'
                          : (group.description.isNotEmpty
                                ? group.description
                                : 'No description'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Unread chats read like unopened messages — bolder
                      // and full-opacity text, same visual cue an unread
                      // row gets in most chat apps — instead of the muted
                      // "already seen" styling every row got before.
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: group.unreadCount > 0
                            ? colorScheme.onSurface.withOpacity(0.85)
                            : colorScheme.onSurface.withOpacity(0.55),
                        fontWeight: group.unreadCount > 0
                            ? FontWeight.w600
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (group.unreadCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  constraints: const BoxConstraints(minWidth: 20),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    group.unreadCount > 99 ? '99+' : '${group.unreadCount}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onError,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (!group.isDirect && group.memberCount != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_alt_rounded,
                        size: 13,
                        color: colorScheme.primary.withOpacity(0.75),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${group.memberCount}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary.withOpacity(0.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurface.withOpacity(0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(
    ThemeData theme,
    String errorMessage,
    Future<void> Function() onRetry,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load chats',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.groups_rounded,
                size: 32,
                color: theme.colorScheme.primary.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Join or create a group to get started',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _openDiscover,
                  icon: const Icon(Icons.explore_outlined, size: 18),
                  label: const Text('Discover'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _createGroup,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 32,
                color: theme.colorScheme.primary.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No conversations yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Message someone to start a conversation',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _openNewMessage,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('New message'),
            ),
          ],
        ),
      ),
    );
  }

  String _initialsForGroup(String name) {
    if (name.isEmpty) return 'G';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Color _colorForName(String name, ColorScheme colorScheme) {
    // Deterministic, pleasant color per group so avatars are distinguishable
    // without needing a real image.
    final palette = [
      colorScheme.primary,
      const Color(0xFF6366F1),
      const Color(0xFF0EA5E9),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEC4899),
      const Color(0xFF8B5CF6),
    ];
    final hash = name.codeUnits.fold<int>(0, (sum, c) => sum + c);
    return palette[hash % palette.length];
  }
}

class _CreateGroupResult {
  final String name;
  final String description;
  final bool isPublic;

  _CreateGroupResult({
    required this.name,
    required this.description,
    required this.isPublic,
  });
}

/// Minimal name/description/visibility form — matches the fields
/// [GroupChatRepository.createGroup] actually accepts, nothing more.
class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isPublic = true;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create group'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.length < 3) return 'At least 3 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Public'),
              subtitle: const Text('Anyone can find and join'),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _CreateGroupResult(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                isPublic: _isPublic,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
