import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

// Thin wrapper around [debugPrint] gated to debug builds. `debugPrint`
// itself still writes to the console in profile/release builds unless
// told otherwise, which used to mean every socket/cache/load diagnostic
// in this screen shipped straight to end users' consoles. Routing all of
// them through here keeps the same call sites and messages (so nothing
// about the logic changes) while making them a no-op outside kDebugMode.
void _log(String message) {
  if (kDebugMode) debugPrint(message);
}

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

  // ✅ Pagination for the activity feed. `_hasMoreActivities` and
  // `_nextCursor` come straight from the server's `meta` block on each
  // page (see ActivityRepository.fetchRecentActivities) — the feed
  // trusts the backend's answer rather than guessing "probably more"
  // off a page being full. `_loadingMoreActivities` is separate from
  // `_loading` on purpose: appending an older page shouldn't blank the
  // whole feed back to the skeleton state the way a fresh load does.
  bool _hasMoreActivities = false;
  int? _nextActivitiesCursor;
  bool _loadingMoreActivities = false;

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

    // Fire the next page a bit before the actual end (400px) so the
    // "load more" round trip has a head start and ideally finishes
    // before the user physically reaches the bottom, rather than
    // making them stare at a spinner they scrolled straight into.
    final nearBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400;
    if (nearBottom) _loadMoreActivities();
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

  // ✅ Static (so it survives State recreation, not just rebuilds): with
  // a flat GoRoute list (no StatefulShellRoute), context.go(Routes.home)
  // tears down and rebuilds this entire widget/State on every bottom-nav
  // round trip. That used to reset _hasLoadedOnce/_loadedForUserId to
  // their initial values on every return to this tab, making the
  // skeleton reappear even though this session had already loaded once.
  // Mirroring the settled state here lets a freshly-created State
  // hydrate itself (see _hydrateFromStaticCache) before its first build
  // instead of starting from scratch. This also gets cleared implicitly
  // on logout, since _loadData() always writes the (now-empty)
  // post-logout state back into these fields too — see the end of
  // _loadData().
  static bool _cacheHasLoadedOnce = false;
  static int? _cachedUserId;
  static User? _cachedUser;
  static List<Activity>? _cachedActivities;
  static Set<String>? _cachedLikedTargetKeys;
  static bool _cachedHasMoreActivities = false;
  static int? _cachedNextActivitiesCursor;
  static int _cachedUnreadNotifications = 0;

  // ✅ Disk-backed twin of the static cache above. The static fields only
  // survive tab-to-tab navigation *within* the same app process — a fresh
  // process (cold start after force-quit, or the very first launch this
  // session) has none of that, so it used to always show the skeleton for
  // a full network round trip. Persisting the last successful load to
  // SharedPreferences as JSON lets a brand-new process paint the previous
  // session's feed almost immediately (a local disk read, not a network
  // call) while a real refresh quietly runs behind it — same idea as
  // Instagram showing your last-seen feed instantly on relaunch. Only one
  // hydration attempt is ever made per process (guarded by the Future
  // below), and _loadData() awaits it before deciding whether to show the
  // skeleton, so the very first real load and the disk hydration can't
  // race each other into showing/hiding the skeleton incorrectly.
  static const String _diskCacheKey = 'cached_home_feed_v1';
  static Future<void>? _diskHydrationFuture;

  Future<void> _hydrateFromDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_diskCacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final activities = (data['activities'] as List<dynamic>? ?? const [])
          .map((e) => Activity.fromJson(e as Map<String, dynamic>))
          .toList();
      final userJson = data['user'] as Map<String, dynamic>?;
      final user = userJson == null ? null : User.fromJson(userJson);
      final likedKeys = (data['likedTargetKeys'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toSet();

      // Mirror into the static (in-memory) cache too, so any other
      // HomeScreen State created later this process (e.g. a second tab
      // switch before the network refresh below has even finished) can
      // hydrate from the fast in-memory path instead of hitting disk again.
      _cacheHasLoadedOnce = true;
      _cachedUserId = data['userId'] as int?;
      _cachedUser = user;
      _cachedActivities = activities;
      _cachedLikedTargetKeys = likedKeys;
      _cachedHasMoreActivities = data['hasMoreActivities'] as bool? ?? false;
      _cachedNextActivitiesCursor = data['nextActivitiesCursor'] as int?;
      _cachedUnreadNotifications = data['unreadNotifications'] as int? ?? 0;

      if (!mounted || _hasLoadedOnce) return;
      setState(() {
        _currentUser = user;
        _activities = activities;
        _likedTargetKeys
          ..clear()
          ..addAll(likedKeys);
        _hasMoreActivities = _cachedHasMoreActivities;
        _nextActivitiesCursor = _cachedNextActivitiesCursor;
        _unreadNotifications = _cachedUnreadNotifications;
        _hasLoadedOnce = true;
        _loadedForUserId = _cachedUserId;
        _loading = false;
      });
    } catch (e) {
      _log('⚠️ HomeScreen: failed to read disk feed cache: $e');
    }
  }

  Future<void> _persistToDiskCache({
    required int? userId,
    required User? user,
    required List<Activity> activities,
    required Set<String> likedTargetKeys,
    required bool hasMoreActivities,
    required int? nextActivitiesCursor,
    required int unreadNotifications,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'userId': userId,
        'user': user?.toJson(),
        // Cap what's persisted to the first page — this cache only exists
        // to paint the initial screen instantly, not to back full-feed
        // pagination offline.
        'activities': activities.take(20).map((a) => a.toJson()).toList(),
        'likedTargetKeys': likedTargetKeys.toList(),
        'hasMoreActivities': hasMoreActivities,
        'nextActivitiesCursor': nextActivitiesCursor,
        'unreadNotifications': unreadNotifications,
      });
      await prefs.setString(_diskCacheKey, payload);
    } catch (e) {
      _log('⚠️ HomeScreen: failed to write disk feed cache: $e');
    }
  }

  // Restores whatever the previous instance of this screen last loaded
  // (see the static fields above), so switching tabs away and back
  // paints real content immediately instead of the skeleton. The
  // regular _loadData() call still runs right after this in initState —
  // but as a quiet background refresh, since _hasLoadedOnce is already
  // true by the time it runs.
  void _hydrateFromStaticCache() {
    if (!_cacheHasLoadedOnce) return;
    _currentUser = _cachedUser;
    _activities = List<Activity>.from(_cachedActivities ?? const []);
    _likedTargetKeys.addAll(_cachedLikedTargetKeys ?? const {});
    _hasMoreActivities = _cachedHasMoreActivities;
    _nextActivitiesCursor = _cachedNextActivitiesCursor;
    _unreadNotifications = _cachedUnreadNotifications;
    _hasLoadedOnce = true;
    _loadedForUserId = _cachedUserId;
    _loading = false;
  }

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
    _hydrateFromStaticCache();
    // Nothing in the in-memory static cache (a genuinely cold process) —
    // kick off the disk hydration read. Only ever started once per
    // process; every later HomeScreen State (or a concurrent _loadData
    // call) just awaits this same Future instead of re-reading disk.
    if (!_hasLoadedOnce) {
      _diskHydrationFuture ??= _hydrateFromDiskCache();
    }
    // Only fire the real load immediately if we already know the actual
    // auth state (e.g. returning to this tab after auto-login already
    // resolved earlier in the session). Calling _loadData() here while
    // AuthService is still mid auto-login would see a `null` userId
    // that isn't really "logged out" — just "not resolved yet" — and
    // that false reading used to get recorded as the loaded state,
    // making the real login moments later look like a user switch and
    // re-flash the skeleton. AuthService.initialize() always calls
    // notifyListeners() once it settles (see its `finally` block),
    // whether that resolves to a real user or a genuine logged-out
    // state, so _onAuthChanged below is guaranteed to fire and load for
    // us in that case.
    if (AuthService().isInitialized) {
      _loadData();
    }
    _connectActivitySocket();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final newUserId = AuthService().userId;

    // Reload when either: this is the first time we're learning the
    // real auth state (the deferred initState() call above resolving),
    // or the logged-in user actually changed (covers both "logged out"
    // -> null and "different user logged in" -> new id).
    if (!_hasLoadedOnce || newUserId != _loadedForUserId) {
      _log(
        '🔄 HomeScreen: auth changed ($_loadedForUserId → $newUserId), reloading',
      );
      _loadData();
      // Re-auth the socket too — it was opened with the previous user's
      // (or no) token, and a stale/absent auth header would leave it
      // silently unable to authenticate against the new session.
      _connectActivitySocket();
    }
  }

  // ✅ shuffle: true randomizes the order of the freshly-fetched page —
  // used for pull-to-refresh (see RefreshIndicator below) so a manual
  // refresh surfaces the feed in a fresh order each time, the same way
  // most social apps mix things up on refresh instead of always showing
  // identical top-to-bottom ordering. Only the newly-fetched first page
  // is shuffled; older activities appended afterwards by
  // _loadMoreActivities() keep loading in real chronological order via
  // their cursor, so pagination integrity beyond the top page is
  // unaffected. Auth-driven and socket-driven calls to _loadData() don't
  // pass this, so they keep the normal chronological order.
  Future<void> _loadData({bool shuffle = false}) async {
    if (!mounted) return;
    // Give a still-in-flight disk hydration a chance to land first — it's
    // a local read (a frame or two), so waiting here doesn't meaningfully
    // delay this load, and it means the skeleton-vs-cached-content check
    // right below always sees the up-to-date _hasLoadedOnce rather than
    // racing the disk read and showing the skeleton needlessly.
    if (!_hasLoadedOnce && _diskHydrationFuture != null) {
      await _diskHydrationFuture;
      if (!mounted) return;
    }
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
    bool hasMoreActivities = false;
    int? nextActivitiesCursor;
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
              _log('⚠️ HomeScreen: failed to load profile: $e');
              return null;
            }),
        ActivityRepository()
            .fetchRecentActivities(limit: 20)
            .then<Object?>((page) => page)
            .catchError((e) {
              _log('❌ HomeScreen: failed to load activities: $e');
              return null;
            }),
        _notificationRepository
            .fetchUnreadCount()
            .then<Object?>((c) => c)
            .catchError((e) {
              _log(
                '⚠️ HomeScreen: failed to load unread notification count: $e',
              );
              return null;
            }),
      ]);

      user = results[0] as User?;

      final fetchedPage = results[1] as ActivityFeedPage?;
      if (fetchedPage != null) {
        // De-duplicate by id so a rebuild/refresh that re-triggers this
        // never piles duplicate rows into the feed.
        final unique = <int, Activity>{};
        for (final a in fetchedPage.activities) {
          unique[a.id] = a;
        }
        activities = unique.values.toList();
        if (shuffle) activities.shuffle(Random());
        hasMoreActivities = fetchedPage.hasMore;
        nextActivitiesCursor = fetchedPage.nextCursor;
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
      _log('⚠️ HomeScreen: no valid session, skipping activity fetch');
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
          _hasMoreActivities = hasMoreActivities;
          _nextActivitiesCursor = nextActivitiesCursor;
        }
      }
      _loading = false;
      _hasLoadedOnce = true;
      _loadedForUserId = loggedInUserId;
      _unreadNotifications = unreadNotifications;

      // Mirror the freshly-settled state into the static cache so the
      // *next* HomeScreen State (created when navigating back to this
      // tab) can hydrate instantly instead of starting from the
      // skeleton again. This also naturally clears the cache on
      // logout, since a logout drives loggedInUserId/activities/etc
      // back to null/empty here too.
      _cacheHasLoadedOnce = true;
      _cachedUserId = loggedInUserId;
      _cachedUser = _currentUser;
      _cachedActivities = List<Activity>.from(_activities);
      _cachedLikedTargetKeys = Set<String>.from(_likedTargetKeys);
      _cachedHasMoreActivities = _hasMoreActivities;
      _cachedNextActivitiesCursor = _nextActivitiesCursor;
      _cachedUnreadNotifications = _unreadNotifications;
    });

    if (!activitiesFailed) {
      // Fire-and-forget: the next cold start reads this back in
      // _hydrateFromDiskCache(). Deliberately not awaited — persisting
      // shouldn't hold up anything else _loadData's caller does.
      unawaited(
        _persistToDiskCache(
          userId: loggedInUserId,
          user: _currentUser,
          activities: _activities,
          likedTargetKeys: _likedTargetKeys,
          hasMoreActivities: _hasMoreActivities,
          nextActivitiesCursor: _nextActivitiesCursor,
          unreadNotifications: _unreadNotifications,
        ),
      );
    }
  }

  // Appends the next-older page of activity to the bottom of the feed.
  // Guarded by _loadingMoreActivities (avoid firing twice while one is
  // already in flight — _onScroll can call this repeatedly as the user
  // keeps scrolling) and by _hasMoreActivities (stop asking once the
  // server has said there's nothing older left).
  Future<void> _loadMoreActivities() async {
    if (!mounted) return;
    if (_loading || _loadingMoreActivities) return;
    if (!_hasMoreActivities || _nextActivitiesCursor == null) return;

    setState(() => _loadingMoreActivities = true);

    try {
      final page = await ActivityRepository().fetchRecentActivities(
        limit: 20,
        beforeId: _nextActivitiesCursor,
      );
      if (!mounted) return;
      setState(() {
        // Same de-duplication reasoning as the initial load: a
        // concurrent live-push (_handleIncomingActivity) could in
        // theory already have inserted one of these rows.
        final unique = <int, Activity>{for (final a in _activities) a.id: a};
        for (final a in page.activities) {
          unique[a.id] = a;
        }
        _activities = unique.values.toList()
          ..sort((a, b) => b.id.compareTo(a.id));
        _hasMoreActivities = page.hasMore;
        _nextActivitiesCursor = page.nextCursor;
      });
    } catch (e) {
      _log('❌ HomeScreen: failed to load more activities: $e');
      // Deliberately don't flip _hasMoreActivities to false here — a
      // network blip loading more shouldn't permanently cut the user
      // off from older content. The next scroll-triggered attempt (or
      // a pull-to-refresh) will just retry from the same cursor.
    } finally {
      if (mounted) setState(() => _loadingMoreActivities = false);
    }
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
        _log('❌ HomeScreen: failed to parse pushed activity: $e');
      }
    });

    socket.onConnect((_) {
      _log('✅ HomeScreen: activity socket connected');
      _activitySocketRetries = 0;
    });
    socket.onConnectError((e) {
      _log('❌ HomeScreen: activity socket connect error: $e');
      _scheduleActivitySocketReconnect();
    });
    socket.onDisconnect((_) {
      _log('🔌 HomeScreen: activity socket disconnected');
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
      _log('❌ HomeScreen: activity socket max reconnect attempts reached');
      return;
    }

    _activitySocketReconnectTimer?.cancel();
    _activitySocketReconnectTimer = Timer(
      Duration(seconds: Config.connectionRetryDelay),
      () {
        if (!mounted) return;
        _log(
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

  // Opens every video post currently in the feed as a fullscreen,
  // vertically swipeable stack starting at the tapped reel — matching
  // Instagram/TikTok Reels, where opening any one reel lets you keep
  // swiping up for the next one and down for the previous, instead of
  // dead-ending on a single video with no way to continue watching.
  void _openReelsViewer(Activity tapped) {
    final reels = _activities.where((a) => a.hasVideo).toList();
    if (reels.isEmpty) return;
    final startIndex = reels.indexWhere((a) => a.id == tapped.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ReelsViewerScreen(
          reels: reels,
          initialIndex: startIndex < 0 ? 0 : startIndex,
          resolveUrl: _resolveAvatarUrl,
          isLiked: (a) => _likedTargetKeys.contains(_targetKey(a)),
          onLike: _handleLike,
          onShare: _shareActivity,
          onOpenComments: _openActivityTarget,
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
            posts: [post],
            initialIndex: 0,
            isOwnPost: (p) =>
                _currentUser != null && p.userId == _currentUser!.id,
            onDelete: isOwnPost
                ? (p) {
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
      _log(
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

  // ✅ FIX: a card's media used to hand both onTap (open) and onDoubleTap
  // (like) to the *same* GestureDetector. Flutter has to wait out
  // kDoubleTapTimeout (~300ms) before it can be sure a tap isn't the
  // first half of a double tap whenever a DoubleTapGestureRecognizer is
  // in the arena — so every single tap on a reel/picture was silently
  // delayed by a third of a second before it opened. Tracking the last
  // tap time by hand keeps each card's GestureDetector down to a single,
  // ungated TapGestureRecognizer (onTap only, no onDoubleTap declared
  // anywhere), so the first tap opens the viewer immediately. A genuine
  // second tap landing within the window is then read as a double-tap
  // like instead of a redundant second "open".
  final Map<int, DateTime> _lastMediaTapAt = {};

  void _handleMediaTap(Activity activity, VoidCallback openAction) {
    final now = DateTime.now();
    final lastTap = _lastMediaTapAt[activity.id];
    if (lastTap != null &&
        now.difference(lastTap) < const Duration(milliseconds: 300)) {
      _lastMediaTapAt.remove(activity.id);
      _handleDoubleTapLike(activity);
    } else {
      _lastMediaTapAt[activity.id] = now;
      openAction();
    }
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
                activity.authorId != null
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
            onTap: () =>
                _handleMediaTap(activity, () => _openActivityTarget(activity)),
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
            Stack(
              alignment: Alignment.center,
              children: [
                _FeedReelPlayer(
                  activityId: activity.id,
                  url: _resolveAvatarUrl(activity.videoUrl)!,
                  accentColor: activity.color,
                  // ✅ FIX: was _openMediaViewer(...), which opened
                  // only the one tapped video with nowhere to go next
                  // — not real "reels" behavior. Now opens the
                  // swipeable fullscreen reels stack (see
                  // _ReelsViewerScreen below), so opening any reel lets
                  // you keep scrolling through every video post in the
                  // feed, TikTok/Instagram-Reels style. Routed through
                  // _handleMediaTap (rather than a wrapping onDoubleTap
                  // GestureDetector) so a single tap opens instantly —
                  // see _handleMediaTap for why.
                  onExpand: () => _handleMediaTap(
                    activity,
                    () => _openReelsViewer(activity),
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
            )
          else if (activity.hasImage)
            GestureDetector(
              onTap: () => _handleMediaTap(
                activity,
                () => _openMediaViewer(
                  url: _resolveAvatarUrl(activity.imageUrl)!,
                  isVideo: false,
                  accentColor: activity.color,
                ),
              ),
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
                      filterQuality: FilterQuality.high,
                      // ✅ FIX: default fadeInDuration is 500ms — on a
                      // cache hit (the common case once memCache/disk
                      // cache is warm) that's 500ms of a visibly
                      // fading-in photo for an image that was already
                      // available instantly. Instagram/Facebook-grade
                      // feeds only fade in on a genuine first fetch;
                      // trimmed to a snappy 120ms so a cached image
                      // simply appears, matching how fast it actually
                      // loaded.
                      fadeInDuration: const Duration(milliseconds: 120),
                      fadeOutDuration: const Duration(milliseconds: 80),
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
                        // ✅ FIX: was `loading: isInFlight`, which swapped
                        // the heart icon out for a spinner for the whole
                        // network round-trip — even though the like
                        // count/heart state above had already flipped
                        // optimistically the instant you tapped. That's
                        // what made liking feel like it "loads before
                        // liking": the number was already right, but the
                        // icon underneath it kept disappearing behind a
                        // spinner. Instagram/Facebook never show a
                        // spinner for a like — it just flips instantly
                        // and syncs silently in the background, rolling
                        // back with a toast only if it actually fails
                        // (still handled in _handleLike below). Tapping
                        // again mid-request is still blocked via
                        // isInFlight on onTap, just without hiding the
                        // icon.
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
                    onRefresh: () => _loadData(shuffle: true),
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

    // One extra trailing slot for the "load more" footer — a spinner
    // while a page is in flight, or a quiet "you're all caught up" once
    // the server's said there's nothing older left. Skipped entirely
    // while a search/filter is active (filteredActivities is a client-
    // side filter of the already-loaded feed, not a new server page, so
    // "load more" doesn't apply to it).
    final showFooter = _searchQuery.isEmpty;
    final itemCount = filteredActivities.length + (showFooter ? 1 : 0);

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index >= filteredActivities.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: _loadingMoreActivities
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : (_hasMoreActivities
                        ? const SizedBox.shrink()
                        : Text(
                            "You're all caught up",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.5,
                              ),
                            ),
                          )),
            ),
          );
        }

        final activity = filteredActivities[index];
        final isLast = index == filteredActivities.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
          child: _FadeSlideIn(
            // ✅ FIX: was 40ms/card up to 240ms delay + a 320ms fade —
            // worst case ~560ms before the last on-screen card had fully
            // settled, which reads as "the feed is still loading" even
            // though the data was already there. Trimmed so every card
            // visible on first paint (typically 2-4 on a phone) is fully
            // settled within ~300ms, matching Instagram/Facebook's own
            // near-instant feed entrance feel.
            delay: Duration(milliseconds: 25 * index.clamp(0, 3)),
            child: RepaintBoundary(
              child: KeyedSubtree(
                key: ValueKey(activity.id),
                child: _buildActivityCard(context, activity),
              ),
            ),
          ),
        );
      }, childCount: itemCount),
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
    duration: const Duration(milliseconds: 200),
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

// Builds a VideoPlayerController for a reel, preferring an already-cached
// local file over the network. This is what makes opening the fullscreen
// reel viewer feel instant for a video that was just visible in the feed
// (or is being revisited): the feed card kicks off caching the first time
// a reel is even partially on-screen, so by the time the fullscreen page
// mounts, the file is usually already on disk and plays with zero network
// wait instead of re-streaming and re-buffering the same video again.
Future<VideoPlayerController> _reelController(String url) async {
  // video_player's web implementation can only play network URLs —
  // VideoPlayerController.file() throws UnimplementedError in the browser,
  // which was breaking every single reel there. The browser's own HTTP
  // cache already handles repeat-request speed-ups for video tags, so
  // there's no upside to the local-file cache path on web anyway — just
  // stream directly there and skip the cache-manager lookup entirely.
  if (!kIsWeb) {
    try {
      final cached = await DefaultCacheManager().getFileFromCache(url);
      if (cached != null) {
        return VideoPlayerController.file(
          cached.file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }
    } catch (_) {
      // Cache lookup failed for any reason — fall through to streaming.
    }
    // Not cached yet: stream directly so playback starts without waiting
    // on a full download, and quietly cache it in the background so the
    // next time this reel is opened it loads instantly from disk.
    unawaited(
      DefaultCacheManager().getSingleFile(url).catchError((_) => File(url)),
    );
  }
  return VideoPlayerController.networkUrl(
    Uri.parse(url),
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
}

/// Shared "this video couldn't be loaded" icon. Used by every video
/// player below ([_FeedReelPlayer], [_MediaViewerScreen], [_ReelPage]) —
/// each one wraps it in its own layout (a tinted card, a bare centered
/// icon, etc.), so only the icon itself — not its surrounding container —
/// is factored out here.
class _VideoUnavailableIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _VideoUnavailableIcon({required this.color, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.videocam_off_outlined, color: color, size: size);
  }
}

/// Shared "video is still loading" spinner, factored out of the three
/// video players for the same reason as [_VideoUnavailableIcon] above.
class _VideoLoadingSpinner extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final Color color;

  const _VideoLoadingSpinner({
    this.size = 36,
    this.strokeWidth = 4,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          color: color,
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
  // ✅ FIX: this used to call _setUp() unconditionally from initState(),
  // which meant every reel the SliverList builds within its cacheExtent
  // — typically 2-3 cards below the fold on a phone — started a full
  // video download the instant the feed painted, competing on bandwidth
  // with the photos and avatars actually on screen. That's the real
  // reason "pics and reels" felt slow to appear together: the first
  // screen's images were fighting off-screen reels for the same
  // connection. A reel's video now only starts downloading the first
  // time VisibilityDetector reports it has *any* on-screen presence —
  // same lazy-load trigger Instagram/Facebook's own feeds use.
  bool _setupStarted = false;

  Future<void> _setUp() async {
    if (_setupStarted) return;
    _setupStarted = true;
    final controller = await _reelController(widget.url);
    if (!mounted) {
      controller.dispose();
      return;
    }
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.setVolume(0); // muted by default, like reels
      setState(() => _initialized = true);
      if (_isVisible) controller.play();
    } catch (e) {
      _log('Reel video failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // Any on-screen presence at all starts the download (so it's ready
    // by the time the user scrolls it fully into view), but actual
    // autoplay still waits for >60% visible — matches the usual
    // reel/story feel without being so twitchy that a half-scrolled card
    // starts and stops repeatedly.
    if (info.visibleFraction > 0 && !_setupStarted) {
      _setUp();
    }
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Caps how tall a feed reel is ever allowed to get. A portrait phone
  // video (very common, e.g. 9:16) sized purely off its own aspect ratio
  // at full card width would end up ~1.8x the card's width tall — that's
  // the "huge reel" problem. Clamping the outer frame to this range and
  // letting the video *contain* itself inside it (see build() below)
  // keeps every reel a similar, tidy, TikTok-card size regardless of the
  // source video's shape, instead of some posts towering over others.
  static const double _minFrameHeight = 220;
  static const double _maxFrameHeight = 360;

  // A raw 9:16 phone video (aspectRatio ≈ 0.56) rendered at its exact
  // native ratio inside the frame above comes out as a narrow centered
  // column with a lot of empty space either side — technically "not
  // cropped", but reads as tiny. Clamping the *displayed* ratio to a
  // wider floor (closer to the 4:5 that Instagram/TikTok use for
  // portrait feed cards) trades a small, even top/bottom crop for a
  // noticeably bigger, more filled-in looking video — the same
  // trade-off every reels-style feed makes. Landscape/near-square clips
  // are already wider than this floor, so they're completely unaffected
  // and still render with zero cropping.
  static const double _minDisplayAspectRatio = 0.78;
  static const double _maxDisplayAspectRatio = 1.91;

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        width: double.infinity,
        height: _minFrameHeight,
        decoration: BoxDecoration(
          color: widget.accentColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: _VideoUnavailableIcon(color: widget.accentColor, size: 32),
      );
    }

    return VisibilityDetector(
      key: Key('reel-${widget.activityId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        // Tapping the reel itself opens the fullscreen swipeable viewer,
        // matching Instagram Reels — the card no longer requires a
        // separate expand button for this. Play/pause is driven purely
        // by scroll visibility now (see _onVisibilityChanged), so a
        // tap-to-toggle in the card is no longer needed.
        onTap: widget.onExpand,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              minHeight: _minFrameHeight,
              maxHeight: _maxFrameHeight,
            ),
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_initialized && _controller != null) ...[
                  // Backdrop: the same video, blown up to cover the
                  // *entire* frame and heavily blurred, sitting behind
                  // the real (sharp) video. This is what actually makes
                  // the margins left over from the clamp above feel
                  // designed rather than empty — the same trick
                  // Facebook/Instagram/Spotify use for media that
                  // doesn't match its container's shape: instead of flat
                  // black bars, the "bars" are a soft, on-brand blur of
                  // the clip itself. A dark scrim on top keeps the sharp
                  // foreground video readable against it.
                  Positioned.fill(
                    child: ClipRect(
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 24,
                          sigmaY: 24,
                          tileMode: TileMode.decal,
                        ),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black38),
                    ),
                  ),
                  // Foreground: Center + AspectRatio sizes the box as big
                  // as possible inside the fixed-height frame — but using
                  // a *clamped* ratio (not the video's raw one) is what
                  // actually enlarges a narrow portrait clip: it gives
                  // the box more width to grow into. FittedBox(fit:
                  // cover) then fills that (possibly wider-than-native)
                  // box with the real video, cropping evenly top/bottom
                  // only for the narrow case — a landscape clip's ratio
                  // is already within the clamp range, so its box matches
                  // the video exactly and cover crops nothing at all.
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio.clamp(
                        _minDisplayAspectRatio,
                        _maxDisplayAspectRatio,
                      ),
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: AnimatedBuilder(
                              animation: _controller!,
                              builder: (context, child) => Stack(
                                fit: StackFit.expand,
                                children: [
                                  VideoPlayer(_controller!),
                                  // Reflects the controller's *actual*
                                  // play state — which can change from
                                  // autoplay-on-scroll (not just the
                                  // manual tap-to-toggle), so this has to
                                  // listen to the controller itself
                                  // rather than rely on local setState
                                  // calls.
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
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else
                  const _VideoLoadingSpinner(size: 26, strokeWidth: 2),
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
              ],
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
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      setState(() => _initialized = true);
      controller.play();
    } catch (e) {
      _log('Media viewer video failed to load: $e');
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
        filterQuality: FilterQuality.high,
        // Same URL as the feed thumbnail, so this is almost always a
        // cache hit — no fade needed, it should just appear.
        fadeInDuration: const Duration(milliseconds: 100),
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
      return _VideoUnavailableIcon(color: widget.accentColor);
    }
    if (!_initialized || _controller == null) {
      return const _VideoLoadingSpinner();
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

// ==========================================
// FULLSCREEN REELS VIEWER (swipeable, TikTok/IG-Reels style)
// ==========================================

/// Opened when a feed reel's expand button is tapped. Shows every video
/// post currently loaded in the feed as a vertical, fullscreen,
/// swipeable stack — swipe up for the next reel, down for the previous
/// one. Only the current page's video plays; every other page pauses
/// (and the ones more than one page away are never even built, since
/// PageView.builder only keeps the current + adjacent pages alive) so a
/// long reel session doesn't leave a dozen video decoders running at
/// once.
class _ReelsViewerScreen extends StatefulWidget {
  final List<Activity> reels;
  final int initialIndex;
  final String? Function(String?) resolveUrl;
  final bool Function(Activity) isLiked;
  final Future<void> Function(Activity) onLike;
  final void Function(Activity) onShare;
  final void Function(Activity) onOpenComments;

  const _ReelsViewerScreen({
    required this.reels,
    required this.initialIndex,
    required this.resolveUrl,
    required this.isLiked,
    required this.onLike,
    required this.onShare,
    required this.onOpenComments,
  });

  @override
  State<_ReelsViewerScreen> createState() => _ReelsViewerScreenState();
}

class _ReelsViewerScreenState extends State<_ReelsViewerScreen> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _currentIndex = widget.initialIndex;

  // Local, instantly-updated like state for this viewer — mirrors the
  // usual optimistic-update pattern used everywhere else in the app
  // (see _HomeScreenState._handleLike / TimelinePostViewer._toggleLike)
  // so tapping the heart here flips it immediately, then syncs to the
  // real backend (and the feed underneath) via widget.onLike in the
  // background.
  late final Map<int, bool> _liked = {
    for (final a in widget.reels) a.id: widget.isLiked(a),
  };
  late final Map<int, int> _likeCounts = {
    for (final a in widget.reels) a.id: a.likeCount ?? 0,
  };
  final Set<int> _inFlight = {};

  void _toggleLike(Activity activity) {
    if (_inFlight.contains(activity.id)) return;
    final wasLiked = _liked[activity.id] ?? false;
    setState(() {
      _inFlight.add(activity.id);
      _liked[activity.id] = !wasLiked;
      _likeCounts[activity.id] =
          ((_likeCounts[activity.id] ?? 0) + (wasLiked ? -1 : 1)).clamp(
            0,
            1 << 30,
          );
    });
    widget.onLike(activity).whenComplete(() {
      if (mounted) setState(() => _inFlight.remove(activity.id));
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.reels.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, index) {
              final activity = widget.reels[index];
              final url = widget.resolveUrl(activity.videoUrl);
              if (url == null) return const SizedBox.shrink();
              return _ReelPage(
                activity: activity,
                url: url,
                isActive: index == _currentIndex,
                liked: _liked[activity.id] ?? false,
                likeCount: _likeCounts[activity.id] ?? 0,
                onLike: () => _toggleLike(activity),
                onShare: () => widget.onShare(activity),
                onOpenComments: () => widget.onOpenComments(activity),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single fullscreen reel page — cover-fit video, tap to play/pause,
/// double-tap to like with a heart burst, and a right-side action rail
/// (like/comment/share/mute) matching Instagram/TikTok Reels' layout.
class _ReelPage extends StatefulWidget {
  final Activity activity;
  final String url;
  final bool isActive;
  final bool liked;
  final int likeCount;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onOpenComments;

  const _ReelPage({
    required this.activity,
    required this.url,
    required this.isActive,
    required this.liked,
    required this.likeCount,
    required this.onLike,
    required this.onShare,
    required this.onOpenComments,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;
  bool _muted = false; // fullscreen reels default to sound on, like IG
  bool _showHeartBurst = false;
  Timer? _heartBurstTimer;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    final controller = await _reelController(widget.url);
    if (!mounted) {
      controller.dispose();
      return;
    }
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      setState(() => _initialized = true);
      if (widget.isActive) controller.play();
    } catch (e) {
      _log('Reel page video failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Swiping to/away from this page — start it over and play, or pause,
    // so only the reel actually on screen is ever decoding frames.
    if (widget.isActive != oldWidget.isActive) {
      final controller = _controller;
      if (controller != null && _initialized) {
        if (widget.isActive) {
          controller.seekTo(Duration.zero);
          controller.play();
        } else {
          controller.pause();
        }
      }
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
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  void _handleDoubleTap() {
    if (!widget.liked) widget.onLike();
    _heartBurstTimer?.cancel();
    setState(() => _showHeartBurst = true);
    _heartBurstTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHeartBurst = false);
    });
  }

  @override
  void dispose() {
    _heartBurstTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    return GestureDetector(
      onTap: _togglePlayPause,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_failed)
            const Center(
              child: _VideoUnavailableIcon(color: Colors.white54, size: 56),
            )
          else if (_initialized && _controller != null)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            const _VideoLoadingSpinner(),
          if (_initialized &&
              _controller != null &&
              !_controller!.value.isPlaying)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 72,
              ),
            ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showHeartBurst ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Center(
                child: Icon(
                  Icons.favorite,
                  color: Colors.white,
                  size: 96,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 16)],
                ),
              ),
            ),
          ),
          // Bottom scrim so the caption/actions stay readable over any
          // video content, same trick Instagram/TikTok Reels use.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 88,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: activity.authorId == null
                      ? null
                      : () => openUserProfile(
                          context,
                          activity.authorId,
                          knownUsername: activity.authorName,
                          knownProfilePicture: activity.authorAvatarUrl,
                        ),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (activity.authorId != null) ...[
                        UserAvatar(
                          profilePicture: activity.authorAvatarUrl,
                          size: 28,
                          // The row above already handles the tap (and
                          // covers the name label too) — the avatar's
                          // own default tap-to-profile would just be a
                          // redundant, smaller-hitbox duplicate of it.
                          onTap: () {},
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          activity.authorName ?? activity.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (activity.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    activity.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 28,
            child: Column(
              children: [
                GestureDetector(
                  onTap: widget.onLike,
                  child: AnimatedScale(
                    scale: widget.liked ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      widget.liked ? Icons.favorite : Icons.favorite_border,
                      color: widget.liked ? Colors.redAccent : Colors.white,
                      size: 32,
                      shadows: const [
                        Shadow(color: Colors.black45, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.likeCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: widget.onOpenComments,
                  child: const Icon(
                    Icons.mode_comment_outlined,
                    color: Colors.white,
                    size: 30,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: widget.onShare,
                  child: const Icon(
                    Icons.share_outlined,
                    color: Colors.white,
                    size: 28,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: _toggleMute,
                  child: Icon(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 28,
                    shadows: const [
                      Shadow(color: Colors.black45, blurRadius: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
