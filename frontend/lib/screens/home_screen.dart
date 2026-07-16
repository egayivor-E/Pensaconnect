import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pensaconnect/services/api_service.dart';
import 'package:pensaconnect/services/auth_service.dart';

import '../config/config.dart';
import '../widgets/app_drawer.dart';
import '../widgets/chat_options_sheet.dart';
import '../widgets/timeline_post_viewer.dart';
import '../widgets/user_avatar.dart';
import '../repositories/activity_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/testimony_repository.dart';
import '../repositories/forum_repository.dart';
import '../repositories/prayer_repository.dart';
import '../repositories/timeline_post_repository.dart';
import '../repositories/notification_repository.dart';
import '../models/activity.dart';
import '../models/user.dart';
import '../utils/activity_target.dart';
import '../utils/profile_navigation.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  User? _currentUser;
  List<Activity> _activities = [];
  bool _loading = true;
  bool _activitiesFailed = false;
  // Tracks whether we've ever successfully painted real content for the
  // current user. Used so a *reload* (pull-to-refresh, auth-state ping,
  // socket reconnect) doesn't blank the whole feed back to the skeleton
  // and force the user to stare at placeholders again for the round trip
  // — only the very first load (or a genuine user switch) should do that.
  bool _hasLoadedOnce = false;
  final NotificationRepository _notificationRepository =
      NotificationRepository();
  int _unreadNotifications = 0;

  // ✅ Search + quick actions now scroll away with the rest of the feed
  // instead of staying pinned. This controller/flag pair replaces that
  // pinned header with a small floating search button that fades in at
  // the top-right once the real search field has scrolled out of view,
  // so search is still reachable without permanently pinning it.
  final ScrollController _scrollController = ScrollController();
  bool _showMiniSearch = false;
  // ✅ Raised from 170 -> 260 so the mini search button only appears once
  // we're clearly past the header/quick-actions row, instead of popping
  // in mid-way through the first feed card (where its floating position
  // could visually clash with that card's own content/action bar).
  static const double _miniSearchScrollThreshold = 260;

  void _onScroll() {
    final shouldShow = _scrollController.offset > _miniSearchScrollThreshold;
    if (shouldShow != _showMiniSearch) {
      setState(() => _showMiniSearch = shouldShow);
    }
  }

  Future<void> _revealSearch() async {
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    if (mounted) _searchFocusNode.requestFocus();
  }

  // Tracks which user's data is currently loaded, and listens for
  // AuthService changes so this screen stays in sync across login/logout
  // even if it isn't recreated (e.g. it's still mounted underneath a
  // pushed route when the auth state changes).
  int? _loadedForUserId;
  late final VoidCallback _authListener;

  // ✅ Dedicated connection just for live "new_activity" pushes, separate
  // from SocketIoService (which is scoped to per-group-chat rooms and has
  // no notion of a standing, app-wide connection). Kept deliberately small
  // and self-contained here rather than extending that shared service, to
  // avoid touching its already-intricate reconnect/typing/room logic for
  // an unrelated feature.
  io.Socket? _activitySocket;
  Timer? _activitySocketReconnectTimer;
  int _activitySocketRetries = 0;
  // ✅ Guards against _connectActivitySocket() being called again while a
  // previous call is still mid-flight (see that method's doc comment for
  // why this happens routinely: initState() calls it immediately, then
  // _onAuthChanged() calls it again moments later once auto-login
  // resolves). Each call captures the generation at entry and checks it
  // again after its async gaps; a call that's no longer current bails out
  // instead of tearing down a socket a *newer* call already owns.
  int _activitySocketConnectGeneration = 0;

  // --- Feed engagement ---
  // ✅ Keyed by the underlying (targetType, targetId) the activity points
  // at — NOT the activity log row's own id. A "like" is a property of the
  // real content (a prayer request, testimony, etc.), not of any single
  // feed entry about it. Praying, for example, can produce a *new*
  // Activity row on the backend; if this set were keyed by activity.id,
  // that new row would show up unliked on the very next refresh even
  // though the user already prayed for the same underlying request.
  // Keying on the target instead means the liked state stays correct no
  // matter which activity row currently represents that target in the feed.
  final Set<String> _likedTargetKeys = {};
  // Guards against a fast double-tap firing two toggle requests before
  // the first one resolves. Same target-based keying as above, so two
  // different feed rows for the same target can't race each other either.
  final Set<String> _actionInFlight = {};
  int? _heartBurstKey;
  Timer? _heartBurstTimer;

  // Composite key identifying the real content an activity points at.
  // Only meaningful when activity.targetId != null (callers already gate
  // on that via ActivityTargetInfo.canLike before using this).
  String _targetKey(Activity activity) =>
      '${activity.targetType}:${activity.targetId}';

  static const List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.calendar_today_rounded,
      'title': 'Events',
      'route': '/events',
      'color': Color(0xFF3B82F6),
    },
    {
      'icon': Icons.menu_book_rounded,
      'title': 'Bible Study',
      'route': '/bible',
      'color': Color(0xFF10B981),
    },
    {
      'icon': Icons.music_note_rounded,
      'title': 'Worship',
      'route': '/worship',
      'color': Color(0xFFA855F7),
    },
    {
      'icon': Icons.live_tv_rounded,
      'title': 'Live',
      'route': '/live',
      'color': Color(0xFFEF4444),
    },
    {
      'icon': Icons.forum_rounded,
      'title': 'Discussions',
      'route': '/forums',
      'color': Color(0xFFF97316),
    },
    {
      'icon': Icons.self_improvement_rounded,
      'title': 'Prayer Wall',
      'route': '/prayer-wall',
      'color': Color(0xFF14B8A6),
    },
    {
      'icon': Icons.auto_stories_rounded,
      'title': 'Testimonies',
      'route': '/testimonies',
      'color': Color(0xFFEC4899),
    },
    {
      'icon': Icons.chat_bubble_rounded,
      'title': 'Group Chats',
      'route': '/group-chats',
      'color': Color(0xFF6366F1),
    },
  ];

  @override
  void initState() {
    super.initState();
    _authListener = _onAuthChanged;
    AuthService().addListener(_authListener);
    _scrollController.addListener(_onScroll);
    _loadData();
    _connectActivitySocket();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final newUserId = AuthService().userId;

    // Only reload if the logged-in user actually changed (covers both
    // "logged out" -> null and "different user logged in" -> new id).
    if (newUserId != _loadedForUserId) {
      debugPrint(
        '🔄 HomeScreen: auth changed ($_loadedForUserId → $newUserId), reloading',
      );
      _loadData();
      // Re-auth the socket too — it was opened with the previous user's
      // (or no) token, and a stale/absent auth header would leave it
      // silently unable to authenticate against the new session.
      _connectActivitySocket();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final loggedInUserId = AuthService().userId;
    // A genuine user switch (login/logout/different account) means the
    // data on screen belongs to someone else and must not linger — that
    // case still gets the full skeleton treatment. A same-user reload
    // (pull-to-refresh, the auth-ping in didChangeDependencies, a socket
    // reconnect) should just refresh quietly with the old content still
    // visible, instead of flashing back to placeholders and making every
    // reload feel like a slow first load.
    final isUserSwitch = loggedInUserId != _loadedForUserId;
    final showSkeleton = !_hasLoadedOnce || isUserSwitch;
    setState(() {
      if (showSkeleton) _loading = true;
      _activitiesFailed = false;
    });

    User? user;
    List<Activity> activities = [];
    bool activitiesFailed = false;
    // Rebuilt fresh from each load's `hasLiked` flags below rather than
    // merged into the old set — the server is the source of truth for
    // like state, so a refresh should fully replace it, not just add to it.
    final likedTargetKeys = <String>{};

    // ✅ Uses the actual token source (ApiService/secure storage), not
    // SharedPreferences['auth_token'] — nothing ever wrote a token
    // there, so that lookup was always null and getCurrentUser() never
    // ran with real credentials.
    final token = await ApiService.getToken();

    int unreadNotifications = 0;

    if (token != null && loggedInUserId != null) {
      // Profile, activity feed, and unread count are three independent
      // endpoints, but were previously awaited one after another —
      // making every load AND every pull-to-refresh take the sum of all
      // three round trips instead of the slowest one. Firing them with
      // Future.wait runs them concurrently while still isolating each
      // one's failure (a slow/broken profile endpoint still shouldn't
      // blank out an otherwise-working feed).
      final results = await Future.wait([
        UserRepository()
            .getCurrentUser(token)
            .then<Object?>((u) => u)
            .catchError((e) {
              debugPrint('⚠️ HomeScreen: failed to load profile: $e');
              return null;
            }),
        ActivityRepository()
            .fetchRecentActivities(limit: 20)
            .then<Object?>((a) => a)
            .catchError((e) {
              debugPrint('❌ HomeScreen: failed to load activities: $e');
              return null;
            }),
        _notificationRepository
            .fetchUnreadCount()
            .then<Object?>((c) => c)
            .catchError((e) {
              debugPrint(
                '⚠️ HomeScreen: failed to load unread notification count: $e',
              );
              return null;
            }),
      ]);

      user = results[0] as User?;

      final fetched = results[1] as List<Activity>?;
      if (fetched != null) {
        // De-duplicate by id so a rebuild/refresh that re-triggers this
        // never piles duplicate rows into the feed.
        final unique = <int, Activity>{};
        for (final a in fetched) {
          unique[a.id] = a;
        }
        activities = unique.values.toList();
        // ✅ Hydrate liked state from the server's per-activity `hasLiked`
        // flag, keyed the same way _targetKey() does, so a fresh app
        // launch (or any refresh) shows previously-liked/prayed items as
        // already liked instead of resetting to "nothing liked" every time.
        for (final a in activities) {
          if (a.hasLiked && a.targetId != null) {
            likedTargetKeys.add(_targetKey(a));
          }
        }
      } else {
        activitiesFailed = true;
      }

      unreadNotifications = results[2] as int? ?? 0;
    } else {
      debugPrint('⚠️ HomeScreen: no valid session, skipping activity fetch');
    }

    if (!mounted) return;
    setState(() {
      if (activitiesFailed && !showSkeleton) {
        // A background refresh (pull-to-refresh, auth ping, socket
        // reconnect) failed — leave whatever's already on screen alone
        // instead of replacing a working feed with an empty/error state.
        // The next successful refresh will replace it normally.
      } else {
        _currentUser = user;
        _activities = activities;
        _activitiesFailed = activitiesFailed;
        if (!activitiesFailed) {
          _likedTargetKeys
            ..clear()
            ..addAll(likedTargetKeys);
        }
      }
      _loading = false;
      _hasLoadedOnce = true;
      _loadedForUserId = loggedInUserId;
      _unreadNotifications = unreadNotifications;
    });
  }

  // ✅ Opens a standing connection just to receive "new_activity" broadcasts
  // (see backend/api/v1/utils.py's broadcast_new_activity) so activity
  // created elsewhere shows up here live, without pulling to refresh.
  //
  // Called from both initState() (immediately, before auth may have
  // resolved) and _onAuthChanged() (again, moments later, once
  // auto-login actually completes) — so two calls landing within
  // milliseconds of each other is the normal case here, not an edge
  // case. Without the generation guard below, the second call's
  // "tear down the old socket" step could fire while the first call's
  // socket was still mid-handshake, producing "WebSocket is closed
  // before the connection is established" in the console. The guard
  // makes only the most recent call actually own `_activitySocket`;
  // any call that's been superseded by a newer one quietly bails out
  // after its `await` instead of racing it.
  Future<void> _connectActivitySocket() async {
    if (!Config.enableLiveChat) return;

    final myGeneration = ++_activitySocketConnectGeneration;

    final token = await ApiService.getToken();
    if (token == null) return; // no session yet — _onAuthChanged will retry
    if (myGeneration != _activitySocketConnectGeneration) {
      return; // a newer call started while we were awaiting the token
    }

    _activitySocket?.offAny();
    _activitySocket?.disconnect();
    _activitySocket?.dispose();

    final options = io.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .setPath('/socket.io')
        .setExtraHeaders({'Authorization': 'Bearer $token'})
        .setQuery({'token': token})
        // ✅ Socket.IO's built-in reconnection re-uses the token captured
        // in this closure forever, so once it expires every auto-reconnect
        // fails with "Signature has expired". Reconnection is instead
        // handled manually below (_scheduleActivitySocketReconnect ->
        // _connectActivitySocket), which re-reads the token from
        // ApiService fresh on every attempt.
        .disableReconnection()
        .disableAutoConnect()
        .build();

    if (myGeneration != _activitySocketConnectGeneration) {
      return; // superseded again while building options — don't connect
    }

    final socket = io.io(Config.websocketUrl, options);
    _activitySocket = socket;
    _activitySocketRetries = 0;

    socket.on('new_activity', (data) {
      try {
        final Map<String, dynamic> json = data is List
            ? Map<String, dynamic>.from(data.first as Map)
            : Map<String, dynamic>.from(data as Map);
        _handleIncomingActivity(Activity.fromJson(json));
      } catch (e) {
        debugPrint('❌ HomeScreen: failed to parse pushed activity: $e');
      }
    });

    socket.onConnect((_) {
      debugPrint('✅ HomeScreen: activity socket connected');
      _activitySocketRetries = 0;
    });
    socket.onConnectError((e) {
      debugPrint('❌ HomeScreen: activity socket connect error: $e');
      _scheduleActivitySocketReconnect();
    });
    socket.onDisconnect((_) {
      debugPrint('🔌 HomeScreen: activity socket disconnected');
      _scheduleActivitySocketReconnect();
    });

    socket.connect();
  }

  // ✅ Manual reconnect with backoff, capped at Config.maxConnectionRetries,
  // mirroring SocketIoService's group-chat retry policy. Always goes back
  // through _connectActivitySocket so a fresh token is read on every try.
  void _scheduleActivitySocketReconnect() {
    if (!mounted || !Config.enableLiveChat) return;

    _activitySocketRetries++;
    if (_activitySocketRetries > Config.maxConnectionRetries) {
      debugPrint(
        '❌ HomeScreen: activity socket max reconnect attempts reached',
      );
      return;
    }

    _activitySocketReconnectTimer?.cancel();
    _activitySocketReconnectTimer = Timer(
      Duration(seconds: Config.connectionRetryDelay),
      () {
        if (!mounted) return;
        debugPrint(
          '🔄 HomeScreen: reconnecting activity socket (attempt $_activitySocketRetries)...',
        );
        _connectActivitySocket();
      },
    );
  }

  // Merges one freshly-pushed activity into the feed. Deliberately checks
  // for an existing id before touching state at all — a duplicate push
  // (e.g. a stray re-emit, or a race with a pull-to-refresh that already
  // fetched the same row) must never insert a second card for it.
  //
  // ✅ Also hydrates the liked state from the activity's own `hasLiked`
  // flag in the SAME setState that adds the card. Previously this method
  // only touched `_activities`, so a pushed activity that the current
  // user had already liked (e.g. liked from another device/tab) would
  // render with an unliked heart until the next full _loadData() — the
  // post was rendering before its like state had actually loaded.
  void _handleIncomingActivity(Activity activity) {
    if (!mounted) return;
    if (_activities.any((a) => a.id == activity.id)) return;
    setState(() {
      _activities = [activity, ..._activities];
      if (activity.hasLiked && activity.targetId != null) {
        _likedTargetKeys.add(_targetKey(activity));
      }
    });
  }

  @override
  void dispose() {
    AuthService().removeListener(_authListener);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _heartBurstTimer?.cancel();
    _activitySocketReconnectTimer?.cancel();
    _activitySocket?.offAny();
    _activitySocket?.disconnect();
    _activitySocket?.dispose();
    super.dispose();
  }

  Widget _buildProfileAvatar(ThemeData theme) {
    if (_currentUser == null) {
      return CircleAvatar(
        radius: 19,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.person,
          color: theme.colorScheme.onPrimaryContainer,
          size: 20,
        ),
      );
    }

    return UserAvatar(profilePicture: _currentUser!.profilePicture, size: 38);
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: (value) => setState(() => _searchQuery = value),
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search features & activity',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.4),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: theme.colorScheme.onSurface.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  // Compact quick-action chip used in the horizontal row that replaces
  // a full-page icon grid — same feature data, much lower visual weight
  // so the activity feed can be the star of the screen.
  //
  // ✅ Lightened from a bold saturated gradient + heavy drop shadow +
  // white glyph to a soft, low-opacity tint with the icon drawn in the
  // feature's own color. Reads as gentle/airy instead of heavy, while
  // still keeping each feature visually distinct by color.
  Widget _buildQuickAction(BuildContext context, Map<String, dynamic> feature) {
    final theme = Theme.of(context);
    final color = feature['color'] as Color;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push(feature['route'] as String),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.12),
                ),
                child: Icon(
                  feature['icon'] as IconData,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                feature['title'] as String,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Activity author avatars come back as a relative path (same as
  // User.profile_picture), not a full URL — resolve against
  // Config.baseUrl the same way _buildProfileAvatar does for the
  // current user.
  String? _resolveAvatarUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = Config.baseUrl.endsWith('/')
        ? Config.baseUrl.substring(0, Config.baseUrl.length - 1)
        : Config.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  // Opens the full-size media viewer for a feed image or video — tapping
  // the cropped card thumbnail alone was a dead end before (no way to see
  // the whole, uncropped image or save it). BoxFit.contain here means
  // nothing gets cut off or overlaps the frame the way the card's
  // BoxFit.cover thumbnail can.
  void _openMediaViewer({
    required String url,
    required bool isVideo,
    required Color accentColor,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MediaViewerScreen(
          url: url,
          isVideo: isVideo,
          accentColor: accentColor,
        ),
      ),
    );
  }

  // Opens the real content an activity refers to, when we have somewhere
  // to send the user — testimony and forum_thread both have live detail
  // screens; prayer_request doesn't (yet), so tapping does nothing for
  // those rather than dead-ending on a broken route.
  void _openActivityTarget(Activity activity) {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canOpenDetail || activity.targetId == null) return;

    switch (activity.targetType) {
      case 'testimony':
        context.push('/testimonies/${activity.targetId}');
        break;
      case 'forum_thread':
        context.push(
          '/threads/${activity.targetId}',
          extra: {'title': activity.title},
        );
        break;
      case 'post':
        context.push(
          '/posts/${activity.targetId}',
          extra: {'threadId': activity.threadId ?? 0},
        );
        break;
      case 'timeline_post':
      case 'timeline_post_comment':
        // Both point at the same underlying post (targetId is the
        // post's id in both cases — a comment's Activity row still
        // targets the post it was made on, not the comment itself).
        // There's no go_router path for a single timeline post, so
        // fetch it and push the same viewer ProfileScreen uses,
        // imperatively rather than via context.push.
        _openTimelinePostFromActivity(activity);
        break;
    }
  }

  // Fetches the full TimelinePost by id and opens it in the same
  // full-screen viewer ProfileScreen's grid uses. Imperative
  // Navigator.push (not context.push) because there's no registered
  // go_router route for a single timeline post today, and
  // TimelinePostViewer needs a complete TimelinePost object rather than
  // just an id.
  Future<void> _openTimelinePostFromActivity(Activity activity) async {
    final postId = activity.targetId;
    if (postId == null) return;
    try {
      final post = await TimelinePostRepository().fetchPostById(postId);
      if (!mounted) return;
      final isOwnPost = _currentUser != null && post.userId == _currentUser!.id;
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (_, __, ___) => TimelinePostViewer(
            post: post,
            isOwnPost: isOwnPost,
            onDelete: isOwnPost
                ? () {
                    Navigator.pop(context);
                    // Home only shows the Activity log entry, not the
                    // post itself, so nothing in _activities needs to
                    // change when the underlying post is deleted from
                    // this viewer.
                  }
                : null,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't open that post: $e")));
    }
  }

  // Routes a like to whichever real endpoint backs this activity's
  // target — there's no "like an activity" endpoint, because an
  // Activity is a log entry, not content of its own. Optimistically
  // flips the heart AND adjusts the visible count, then rolls both back
  // if the API call fails.
  //
  // ✅ Previously this only toggled `_likedTargetKeys` (the heart icon).
  // `activity.likeCount` was never touched, so the "Like · 12" label sat
  // frozen at whatever the last full feed fetch returned — tapping like
  // flipped the heart but the number next to it didn't move until a
  // pull-to-refresh. Now the specific Activity instance in `_activities`
  // is replaced with an updated copy every time, same as the heart, so
  // both change in the same frame and both roll back together on error.
  Future<void> _handleLike(Activity activity) async {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canLike || activity.targetId == null) return;
    final key = _targetKey(activity);
    if (_actionInFlight.contains(key)) return;

    final wasLiked = _likedTargetKeys.contains(key);
    final index = _activities.indexWhere((a) => a.id == activity.id);

    void applyCountDelta(int delta) {
      if (index == -1) return;
      final current = _activities[index];
      final newCount = ((current.likeCount ?? 0) + delta).clamp(0, 1 << 30);
      _activities[index] = current.copyWith(likeCount: newCount);
    }

    setState(() {
      _actionInFlight.add(key);
      wasLiked ? _likedTargetKeys.remove(key) : _likedTargetKeys.add(key);
      applyCountDelta(wasLiked ? -1 : 1);
    });

    try {
      switch (activity.targetType) {
        case 'testimony':
          await TestimonyRepository().toggleLike(activity.targetId!);
          break;
        case 'forum_thread':
          await ForumRepository().toggleLikeThread(activity.targetId!);
          break;
        case 'post':
          await ForumRepository().toggleLike(activity.targetId!);
          break;
        case 'prayer_request':
          await PrayerRepository().togglePrayerById(activity.targetId!);
          break;
        case 'timeline_post':
        case 'timeline_post_comment':
          // Both target types point at the same underlying post
          // (targetId is the post's id in both cases), so both use the
          // same like endpoint — POST /timeline-posts/:id/like — so
          // like state stays consistent with the profile grid/post
          // viewer regardless of which activity row triggered it.
          await TimelinePostRepository().toggleLike(activity.targetId!);
          break;
      }
    } catch (e) {
      debugPrint(
        '❌ Failed to sync like for ${activity.targetType}#${activity.targetId}: $e',
      );
      if (!mounted) return;
      setState(() {
        wasLiked ? _likedTargetKeys.add(key) : _likedTargetKeys.remove(key);
        applyCountDelta(wasLiked ? 1 : -1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't save that — check your connection and try again.",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(key));
    }
  }

  void _handleDoubleTapLike(Activity activity) {
    final info = activityTargetInfo(activity.targetType);
    if (!info.canLike) return;
    if (!_likedTargetKeys.contains(_targetKey(activity))) {
      _handleLike(activity);
    }
    _heartBurstTimer?.cancel();
    setState(() => _heartBurstKey = activity.id);
    _heartBurstTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _heartBurstKey = null);
    });
  }

  // Appends a count to an action bar label when one was provided by the
  // backend (e.g. "Like" -> "Like · 12"). Omits it entirely when null
  // rather than showing a potentially-wrong "0" for target types the
  // backend doesn't batch counts for yet.
  String _withCount(String label, int? count) {
    if (count == null || count <= 0) return label;
    return '$label · $count';
  }

  void _shareActivity(Activity activity) {
    final text = activity.subtitle.isNotEmpty
        ? '${activity.title}\n\n${activity.subtitle}'
        : activity.title;
    Share.share(text);
  }

  // Feed-style post card — header (author identity), content, then a
  // real Like/Comment/Share action bar. Like and Comment only render
  // when the activity has a real backing object with a working endpoint
  // (see ActivityTargetInfo) — Share always works since it just shares
  // the activity's own text.
  Widget _buildActivityCard(BuildContext context, Activity activity) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final info = activityTargetInfo(activity.targetType);
    final isLiked = _likedTargetKeys.contains(_targetKey(activity));
    final isInFlight = _actionInFlight.contains(_targetKey(activity));
    final showBurst = _heartBurstKey == activity.id;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.08 : 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Post header: avatar, author, meta ---
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                activity.hasAuthorAvatar
                    ? UserAvatar(
                        profilePicture: activity.authorAvatarUrl,
                        size: 44,
                        userId: activity.authorId,
                      )
                    : Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: activity.color.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          activity.icon,
                          color: activity.color,
                          size: 22,
                        ),
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.authorName ?? activity.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(activity.icon, size: 12, color: activity.color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              activity.timeAgo,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.5,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- Post content: title + subtitle text (moved above the
          // media, Facebook-style, so the caption always reads first) ---
          GestureDetector(
            onTap: () => _openActivityTarget(activity),
            onDoubleTap: () => _handleDoubleTapLike(activity),
            behavior: HitTestBehavior.opaque,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activity.authorName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            activity.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Text(
                        activity.subtitle,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.75),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!activity.hasImage && !activity.hasVideo)
                  IgnorePointer(
                    child: AnimatedScale(
                      scale: showBurst ? 1.0 : 0.6,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: showBurst ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Icon(
                          info.activeIcon,
                          color: Colors.white,
                          size: 72,
                          shadows: const [
                            Shadow(color: Colors.black38, blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // --- Media: shown at (roughly) its natural proportions,
          // Facebook-style — the whole image/video is always visible,
          // never cropped, scaled to the card width and capped at a
          // sensible max height so a tall portrait or wide panorama
          // doesn't blow out the feed. A video becomes an autoplaying
          // "reel"; otherwise fall back to an image thumbnail if there
          // is one. Both are tappable to open the full media in a
          // dedicated viewer where it can also be downloaded. ---
          if (activity.hasVideo)
            GestureDetector(
              onDoubleTap: () => _handleDoubleTapLike(activity),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _FeedReelPlayer(
                    activityId: activity.id,
                    url: _resolveAvatarUrl(activity.videoUrl)!,
                    accentColor: activity.color,
                    onExpand: () => _openMediaViewer(
                      url: _resolveAvatarUrl(activity.videoUrl)!,
                      isVideo: true,
                      accentColor: activity.color,
                    ),
                  ),
                  IgnorePointer(
                    child: AnimatedScale(
                      scale: showBurst ? 1.0 : 0.6,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: showBurst ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Icon(
                          info.activeIcon,
                          color: Colors.white,
                          size: 72,
                          shadows: const [
                            Shadow(color: Colors.black38, blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (activity.hasImage)
            GestureDetector(
              onTap: () => _openMediaViewer(
                url: _resolveAvatarUrl(activity.imageUrl)!,
                isVideo: false,
                accentColor: activity.color,
              ),
              onDoubleTap: () => _handleDoubleTapLike(activity),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      minHeight: 160,
                      maxHeight: 420,
                    ),
                    width: double.infinity,
                    color: activity.color.withOpacity(0.06),
                    child: CachedNetworkImage(
                      imageUrl: _resolveAvatarUrl(activity.imageUrl)!,
                      fit: BoxFit.contain,
                      memCacheWidth:
                          (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      memCacheHeight:
                          (420 * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      errorWidget: (context, url, error) => Container(
                        height: 200,
                        color: activity.color.withOpacity(0.08),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: activity.color,
                          size: 32,
                        ),
                      ),
                      placeholder: (context, url) => Container(
                        height: 200,
                        color: activity.color.withOpacity(0.06),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: AnimatedScale(
                      scale: showBurst ? 1.0 : 0.6,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: showBurst ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Icon(
                          info.activeIcon,
                          color: Colors.white,
                          size: 72,
                          shadows: const [
                            Shadow(color: Colors.black38, blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (info.canLike || info.canOpenDetail) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outline.withOpacity(0.1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  if (info.canLike)
                    Expanded(
                      child: _ActionBarButton(
                        icon: isLiked ? info.activeIcon : info.icon,
                        label: _withCount(
                          isLiked ? info.activeLabel : info.label,
                          activity.likeCount,
                        ),
                        color: isLiked ? info.activeColor : null,
                        highlighted: isLiked,
                        loading: isInFlight,
                        onTap: isInFlight ? null : () => _handleLike(activity),
                      ),
                    ),
                  if (info.canOpenDetail)
                    Expanded(
                      child: _ActionBarButton(
                        icon: Icons.mode_comment_outlined,
                        label: _withCount('Comment', activity.commentCount),
                        onTap: () => _openActivityTarget(activity),
                      ),
                    ),
                  Expanded(
                    child: _ActionBarButton(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: () => _shareActivity(activity),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: _ActionBarButton(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () => _shareActivity(activity),
              ),
            ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  // Empty state that invites action instead of just announcing absence —
  // avoids the "nobody uses this app" impression a bare "No recent
  // activity" text creates.
  Widget _buildEmptyFeedState(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.15),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 36,
            color: theme.colorScheme.primary.withOpacity(0.6),
          ),
          const SizedBox(height: 12),
          Text(
            "Your feed is just getting started",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Join a discussion, post a prayer request, or check today's devotional — activity from your community will show up here.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => context.push('/forums'),
            child: const Text("Explore Discussions"),
          ),
        ],
      ),
    );
  }

  // Distinct from the empty state — a failed fetch shouldn't read as
  // "nothing has happened yet", it should read as "we couldn't get it".
  Widget _buildFeedErrorState(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 34,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't load recent activity",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Check your connection and try again.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _loadData, child: const Text('Try again')),
        ],
      ),
    );
  }

  Widget _buildNotificationBell(ThemeData theme) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: () async {
            await context.push('/notifications');
            // The badge may be stale after visiting the screen (some
            // notifications likely got marked read there), so refresh it
            // rather than waiting for the next full pull-to-refresh.
            if (mounted) {
              final count = await _notificationRepository.fetchUnreadCount();
              if (mounted) setState(() => _unreadNotifications = count);
            }
          },
          tooltip: 'Notifications',
        ),
        if (_unreadNotifications > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onError,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isLargeScreen = MediaQuery.of(context).size.width >= 800;
    final bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    final filteredFeatures = _features
        .where(
          (f) => (f['title'] as String).toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();

    final filteredActivities = _activities
        .where(
          (a) => a.title.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    PreferredSizeWidget? appBar;
    if (!isIOS) {
      appBar = AppBar(
        title: const Text('PensaConnect'),
        centerTitle: false,
        elevation: 0,
        actions: [
          _buildNotificationBell(theme),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: GestureDetector(
              onTap: () => context.go('/profile'),
              child: _buildProfileAvatar(theme),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: isLargeScreen ? null : const AppDrawer(),
      body: Row(
        children: [
          if (isLargeScreen) const AppDrawer(),
          Expanded(
            child: Container(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: _loadData,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        // --- iOS has no AppBar, so its identity/notifications/
                        // profile access lives inline instead of disappearing. ---
                        if (isIOS)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'PensaConnect',
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  _buildNotificationBell(theme),
                                  GestureDetector(
                                    onTap: () => context.go('/profile'),
                                    child: _buildProfileAvatar(theme),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // --- Greeting header ---
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentUser != null
                                      ? 'Welcome back, ${_currentUser!.username}!'
                                      : 'Welcome back!',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Here's what's happening in your community",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // --- Search + quick actions: scroll away with the
                        // feed like everything else, rather than staying
                        // pinned at the top. A small floating search button
                        // (see the Stack in build()) takes over once this
                        // has scrolled out of view. ---
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                          sliver: SliverToBoxAdapter(
                            child: SizedBox(
                              height: 52,
                              child: _buildSearchField(theme),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
                          sliver: SliverToBoxAdapter(
                            child: SizedBox(
                              height: 92,
                              child: _loading
                                  ? const _QuickActionsSkeleton()
                                  : filteredFeatures.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No matching features',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.5),
                                            ),
                                      ),
                                    )
                                  : ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      itemCount: filteredFeatures.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (context, index) =>
                                          _buildQuickAction(
                                            context,
                                            filteredFeatures[index],
                                          ),
                                    ),
                            ),
                          ),
                        ),

                        // --- Activity feed: the primary content ---
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              'Recent Activity',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: _buildFeedSliver(theme, filteredActivities),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    ),
                  ),
                  // --- Floating mini search: fades/scales in once the
                  // real search field has scrolled out of view, giving a
                  // quick way back to search without pinning it. Sits on
                  // top of a full-width, top-to-transparent gradient scrim
                  // so it always reads as its own translucent bar rather
                  // than stacking directly on whatever card content has
                  // scrolled underneath it. ---
                  Positioned(
                    top: 0,
                    right: 0,
                    left: 0,
                    child: IgnorePointer(
                      ignoring: !_showMiniSearch,
                      child: AnimatedOpacity(
                        opacity: _showMiniSearch ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(0, 12, 16, 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                theme.colorScheme.surfaceVariant.withOpacity(
                                  0.9,
                                ),
                                theme.colorScheme.surfaceVariant.withOpacity(
                                  0.0,
                                ),
                              ],
                            ),
                          ),
                          alignment: Alignment.centerRight,
                          child: AnimatedScale(
                            scale: _showMiniSearch ? 1 : 0.7,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            child: Material(
                              color: theme.colorScheme.surface,
                              shape: const CircleBorder(),
                              elevation: 3,
                              shadowColor: Colors.black.withOpacity(0.15),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _revealSearch,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.7),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (context) => const ChatOptionsSheet(),
          );
        },
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.chat_bubble, color: Colors.white),
      ),
    );
  }

  Widget _buildFeedSliver(ThemeData theme, List<Activity> filteredActivities) {
    if (_loading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: EdgeInsets.only(bottom: index == 2 ? 0 : 14),
            child: const _ActivitySkeletonCard(),
          ),
          childCount: 3,
        ),
      );
    }

    if (_activitiesFailed) {
      return SliverToBoxAdapter(child: _buildFeedErrorState(context, theme));
    }

    if (filteredActivities.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyFeedState(context, theme));
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final activity = filteredActivities[index];
        final isLast = index == filteredActivities.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
          child: _FadeSlideIn(
            delay: Duration(milliseconds: 40 * index.clamp(0, 6)),
            child: KeyedSubtree(
              key: ValueKey(activity.id),
              child: _buildActivityCard(context, activity),
            ),
          ),
        );
      }, childCount: filteredActivities.length),
    );
  }
}

// ==========================================
// FEED ENTRANCE ANIMATION
// ==========================================

/// Small fade + upward-slide wrapper so feed cards ease in rather than
/// popping onto the screen — with a slight per-index stagger, the whole
/// list reads as one deliberate motion instead of a static dump of rows.
class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _FadeSlideIn({required this.child, this.delay = Duration.zero});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ==========================================
// SHIMMER LOADING SKELETONS
// ==========================================

class _QuickActionsSkeleton extends StatelessWidget {
  const _QuickActionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) => SizedBox(
          width: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _SkeletonBlock(width: 56, height: 56, radius: 28),
              SizedBox(height: 8),
              _SkeletonBlock(width: 44, height: 10, radius: 5),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivitySkeletonCard extends StatelessWidget {
  const _ActivitySkeletonCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Shimmer(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SkeletonBlock(width: 44, height: 44, radius: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SkeletonBlock(width: 120, height: 12, radius: 6),
                      SizedBox(height: 8),
                      _SkeletonBlock(width: 90, height: 10, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _SkeletonBlock(width: double.infinity, height: 12, radius: 6),
            const SizedBox(height: 8),
            const _SkeletonBlock(width: 180, height: 12, radius: 6),
            const SizedBox(height: 16),
            const _SkeletonBlock(width: double.infinity, height: 1, radius: 0),
            const SizedBox(height: 10),
            Row(
              children: const [
                Expanded(child: _SkeletonBlock(height: 14, radius: 6)),
                SizedBox(width: 16),
                Expanded(child: _SkeletonBlock(height: 14, radius: 6)),
                SizedBox(width: 16),
                Expanded(child: _SkeletonBlock(height: 14, radius: 6)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBlock({
    this.width = double.infinity,
    required this.height,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Sweeps a soft highlight band left-to-right across its child on a loop.
/// Implemented with a plain `AnimationController` + `ShaderMask` so it has
/// no dependency beyond Flutter itself.
class _Shimmer extends StatefulWidget {
  final Widget child;

  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withOpacity(0.08);
    final highlight = Theme.of(context).colorScheme.onSurface.withOpacity(0.16);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment(-1 - t * 3, 0),
              end: Alignment(1 - t * 3, 0),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ==========================================
// ACTION BAR BUTTON
// ==========================================

/// Single Like/Comment/Share button used in the activity card's action
/// bar. Pulled out as its own widget so all of them stay pixel-identical
/// (equal width, same icon size, same tap target) the way FB/IG action
/// bars do. When `highlighted` is true, it fills with a soft tint of
/// `color` so an active state is legible at a glance, not just from the
/// icon swap.
class _ActionBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool highlighted;
  final bool loading;
  final VoidCallback? onTap;

  const _ActionBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.highlighted = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor =
        color ?? theme.colorScheme.onSurface.withOpacity(0.65);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: highlighted
                  ? effectiveColor.withOpacity(0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: effectiveColor,
                    ),
                  )
                else
                  AnimatedScale(
                    scale: highlighted ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Icon(icon, size: 20, color: effectiveColor),
                  ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: effectiveColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A feed-card video "reel" — muted-autoplay-on-scroll, like TikTok/IG
/// Reels: it plays automatically when enough of the card is on screen,
/// pauses the instant it scrolls away (so many reels in a long feed
/// don't all fight for CPU/bandwidth at once), and starts muted with a
/// tap-to-unmute control since autoplaying sound in a social feed is a
/// bad surprise.
class _FeedReelPlayer extends StatefulWidget {
  final int activityId;
  final String url;
  final Color accentColor;
  final VoidCallback onExpand;

  const _FeedReelPlayer({
    required this.activityId,
    required this.url,
    required this.accentColor,
    required this.onExpand,
  });

  @override
  State<_FeedReelPlayer> createState() => _FeedReelPlayerState();
}

class _FeedReelPlayerState extends State<_FeedReelPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;
  bool _muted = true;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.setVolume(0); // muted by default, like reels
      setState(() => _initialized = true);
      if (_isVisible) controller.play();
    } catch (e) {
      debugPrint('Reel video failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // >60% of the card on screen = "in view" for autoplay purposes —
    // matches the usual reel/story feel without being so twitchy that a
    // half-scrolled card starts and stops repeatedly.
    final visible = info.visibleFraction > 0.6;
    if (visible == _isVisible) return;
    _isVisible = visible;
    final controller = _controller;
    if (controller == null || !_initialized) return;
    if (visible) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _muted = !_muted;
      controller.setVolume(_muted ? 0 : 1);
    });
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_initialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          color: widget.accentColor.withOpacity(0.08),
          alignment: Alignment.center,
          child: Icon(
            Icons.videocam_off_outlined,
            color: widget.accentColor,
            size: 32,
          ),
        ),
      );
    }

    return VisibilityDetector(
      key: Key('reel-${widget.activityId}'),
      onVisibilityChanged: _onVisibilityChanged,
      // Uses the video's real aspect ratio once known — same "never
      // cropped" treatment as the image thumbnail above and the
      // full-screen media viewer — instead of force-fitting every video
      // into a fixed 16:10 box. A portrait phone video (very common)
      // forced into a wide 16:10 box via BoxFit.cover was being zoomed
      // and cropped hard enough to hide most of the frame, which is what
      // read as the video being "covered up"/badly fitted. Falls back to
      // a placeholder ratio only for the brief moment before the
      // controller reports real dimensions.
      //
      // AnimatedSize smooths the one-time jump from the 16:9 placeholder
      // to the real ratio once the video initializes, instead of the
      // card instantly snapping to a new height (which read as content
      // jumping/overlapping the neighboring card for a frame).
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AspectRatio(
          aspectRatio: (_initialized && _controller != null)
              ? _controller!.value.aspectRatio
              : 16 / 9,
          child: GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_initialized && _controller != null)
                    AnimatedBuilder(
                      animation: _controller!,
                      builder: (context, child) => Stack(
                        fit: StackFit.expand,
                        children: [
                          // AspectRatio above already matches the video's
                          // own dimensions exactly, so VideoPlayer can fill
                          // it directly — no FittedBox/cover crop needed.
                          VideoPlayer(_controller!),
                          // Reflects the controller's *actual* play state —
                          // which can change from autoplay-on-scroll (not
                          // just the manual tap-to-toggle), so this has to
                          // listen to the controller itself rather than
                          // rely on local setState calls.
                          if (!_controller!.value.isPlaying)
                            const Center(
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 56,
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: GestureDetector(
                      onTap: _toggleMute,
                      child: CircleAvatar(
                        backgroundColor: Colors.black45,
                        radius: 16,
                        child: Icon(
                          _muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: GestureDetector(
                      onTap: widget.onExpand,
                      child: const CircleAvatar(
                        backgroundColor: Colors.black45,
                        radius: 16,
                        child: Icon(
                          Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
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
}

// ==========================================
// FULL-SCREEN MEDIA VIEWER
// ==========================================

/// Opened when a feed image or video is tapped. Shows the media at its
/// real proportions — `BoxFit.contain` for the image, natural aspect
/// ratio for the video — so nothing is cropped or overlapping the way
/// the feed card's thumbnail necessarily can be. Also exposes a
/// download/open action via `url_launcher`: on web this opens the raw
/// media URL in a new tab, which the browser downloads or displays
/// depending on the file type and the user's settings; on mobile it
/// opens the file externally. There's no bundled file-saving package
/// (e.g. dio + path_provider) in this project yet, so this is the
/// lightest correct option without adding a new dependency.
class _MediaViewerScreen extends StatefulWidget {
  final String url;
  final bool isVideo;
  final Color accentColor;

  const _MediaViewerScreen({
    required this.url,
    required this.isVideo,
    required this.accentColor,
  });

  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _setUpVideo();
  }

  Future<void> _setUpVideo() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      setState(() => _initialized = true);
      controller.play();
    } catch (e) {
      debugPrint('Media viewer video failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _downloadOrOpen() async {
    final uri = Uri.parse(widget.url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download / open',
            onPressed: _downloadOrOpen,
          ),
        ],
      ),
      body: Center(child: widget.isVideo ? _buildVideo() : _buildImage()),
    );
  }

  Widget _buildImage() {
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 4,
      child: CachedNetworkImage(
        imageUrl: widget.url,
        fit: BoxFit.contain,
        errorWidget: (context, url, error) => Icon(
          Icons.broken_image_outlined,
          color: widget.accentColor,
          size: 48,
        ),
        placeholder: (context, url) =>
            const CircularProgressIndicator(color: Colors.white70),
      ),
    );
  }

  Widget _buildVideo() {
    if (_failed) {
      return Icon(
        Icons.videocam_off_outlined,
        color: widget.accentColor,
        size: 48,
      );
    }
    if (!_initialized || _controller == null) {
      return const CircularProgressIndicator(color: Colors.white70);
    }
    final controller = _controller!;
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: GestureDetector(
        onTap: () => setState(() {
          controller.value.isPlaying ? controller.pause() : controller.play();
        }),
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            VideoPlayer(controller),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => controller.value.isPlaying
                  ? const SizedBox.shrink()
                  : const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 64,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
