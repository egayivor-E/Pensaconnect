// lib/screens/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/notification_model.dart';
import '../repositories/notification_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationRepository _repository = NotificationRepository();
  List<AppNotification> _notifications = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final notifications = await _repository.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'new_event':
        return Icons.event_rounded;
      case 'forum_reply':
        return Icons.forum_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Future<void> _handleTap(AppNotification notification) async {
    if (!notification.isRead) {
      // Optimistic — flip it locally right away so the tap feels instant,
      // then fire the request in the background.
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notification.id);
        if (index != -1) {
          _notifications[index] = notification.copyWith(isRead: true);
        }
      });
      _repository.markAsRead(notification.id);
    }

    final url = notification.actionUrl;
    if (url == null || url.isEmpty) return;

    // Only navigate for URLs that map to a real in-app route. Event
    // notifications link to `/events/<id>`, which isn't its own detail
    // route yet, so send those to the events list/calendar instead of
    // a 404. Anything else that starts with a known top-level route
    // (e.g. `/events`, `/forums`) is pushed as-is.
    if (url.startsWith('/events')) {
      context.go('/events');
    } else if (url.startsWith('/')) {
      context.go(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? _buildError(theme)
              : _notifications.isEmpty
                  ? _buildEmpty(theme)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: notification.isRead
                                  ? theme.colorScheme.surfaceVariant
                                  : theme.colorScheme.primaryContainer,
                              child: Icon(
                                _iconFor(notification.type),
                                color: notification.isRead
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              notification.title,
                              style: TextStyle(
                                fontWeight: notification.isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              notification.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              timeago.format(notification.createdAt),
                              style: theme.textTheme.bodySmall,
                            ),
                            onTap: () => _handleTap(notification),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 56,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "You're all caught up",
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'New notifications will show up here.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          const Text("Couldn't load notifications"),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
    );
  }
}
