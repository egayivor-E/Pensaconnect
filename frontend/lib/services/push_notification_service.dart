import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// A screen to navigate to when a push notification is tapped — some
/// routes (like GroupChatDetailScreen) are built from GoRouter's `extra`
/// map rather than the path itself, so a bare path string isn't always
/// enough. See PushNotificationService.pendingRoute.
class PendingPushRoute {
  const PendingPushRoute(this.path, {this.extra});
  final String path;
  final Map<String, dynamic>? extra;
}

/// Handles push notifications end-to-end: Firebase init, permission
/// request, registering this device's token with the backend (see
/// PATCH /users/me/push-token in backend/api/v1/users.py), keeping that
/// token fresh, and surfacing where a tapped notification should take
/// the user.
///
/// IMPORTANT: this only does anything once Firebase is actually
/// configured for this project — a real Firebase project, `flutterfire
/// configure` run against it, and the resulting platform config files
/// (google-services.json / GoogleService-Info.plist / firebase_options.dart)
/// in place. Until then, every method here fails soft: it logs once and
/// does nothing, so the rest of the app behaves exactly as it does
/// today. See docs/PUSH_NOTIFICATIONS_SETUP.md for the one-time setup
/// steps — that part needs whoever owns the Firebase account, not just
/// code.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;
  bool _firebaseAvailable = false;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Route to navigate to once a notification is tapped (app opened from
  /// terminated state, or brought to foreground from background). A
  /// listener (e.g. HomeScreen) can watch this ValueNotifier and clear
  /// it back to null once handled. Kept deliberately simple — one
  /// pending route is enough for "tap a notification, land on the right
  /// screen" without needing a global navigator key threaded through
  /// GoRouter.
  final ValueNotifier<PendingPushRoute?> pendingRoute =
      ValueNotifier<PendingPushRoute?>(null);

  /// Call once per app session, right after a successful login,
  /// register, or auto-login (see AuthProvider). Safe to call more than
  /// once — only the first call in a session does any real work.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseAvailable = true;
    } catch (e) {
      // Expected until Firebase is actually configured for this project
      // (see docs/PUSH_NOTIFICATIONS_SETUP.md) — fail soft, not fatal.
      developer.log(
        'Push notifications unavailable (Firebase not configured yet): $e',
        name: 'PushNotificationService',
      );
      _firebaseAvailable = false;
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }

      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen(_registerToken);

      // App was launched directly from a terminated state by tapping a
      // notification — capture its target route for whoever's watching
      // pendingRoute.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }

      // App was backgrounded (not terminated) and the user tapped the
      // notification to bring it back to the foreground.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      // App was already in the foreground when the push arrived — FCM
      // doesn't show a system tray notification in this case (that's
      // normal platform behavior, not a bug here). Logged for now;
      // screens that show live counts (e.g. the notifications badge)
      // already refresh on their own navigation/pull-to-refresh cycles.
      FirebaseMessaging.onMessage.listen((message) {
        developer.log(
          'Foreground push received: ${message.notification?.title}',
          name: 'PushNotificationService',
        );
      });
    } catch (e) {
      developer.log(
        'Push notification setup failed: $e',
        name: 'PushNotificationService',
      );
    }
  }

  void _handleMessageTap(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;

    // GroupChatDetailScreen is built from GoRouter's `extra` map (see
    // main.dart's '/group-chats/detail' route), not from query params —
    // a bare action_url path can't carry groupId/groupName through, so
    // this type gets its own explicit case rather than a generic
    // action_url string.
    if (type == 'group_message') {
      final groupId = int.tryParse(data['group_id'] ?? '');
      if (groupId != null) {
        pendingRoute.value = PendingPushRoute(
          '/group-chats/detail',
          extra: {
            'groupId': groupId,
            'groupName': data['group_name'] ?? 'Group Chat',
          },
        );
      }
      return;
    }

    final route = data['action_url'] as String?;
    if (route != null && route.isNotEmpty) {
      pendingRoute.value = PendingPushRoute(route);
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await ApiService.patch('users/me/push-token', {'push_token': token});
    } catch (e) {
      developer.log(
        'Failed to register push token: $e',
        name: 'PushNotificationService',
      );
    }
  }

  /// Call on logout so a stale token doesn't keep receiving pushes meant
  /// for whoever logs in on this device next.
  Future<void> clearToken() async {
    if (!_firebaseAvailable) return;
    try {
      await ApiService.patch('users/me/push-token', {'push_token': null});
    } catch (e) {
      developer.log(
        'Failed to clear push token: $e',
        name: 'PushNotificationService',
      );
    }
  }
}

/// Must be a top-level (or static) function — the platform invokes this
/// in its own background isolate when a push arrives while the app
/// isn't running. Registered via FirebaseMessaging.onBackgroundMessage
/// in main.dart. Kept intentionally minimal (just making sure Firebase
/// is initialized so the OS can display the notification) — anything
/// heavier here would slow down every background push delivery.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // Firebase not configured yet — nothing to do.
  }
}
