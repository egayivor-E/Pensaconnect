import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pensaconnect/models/group_message_model.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member.dart';
import '../models/message_model.dart';
import '../models/live_broadcast_model.dart';
import '../repositories/message_repository.dart';
import '../repositories/member_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/live_broadcast_repository.dart';
import '../services/socketio_service.dart';
import '../config/config.dart';
import '../utils/validators.dart';
import '../utils/profile_navigation.dart';

class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({super.key});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  late YoutubePlayerController _controller;
  final List<Member> _members = [];
  final List<Message> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  final MessageRepository _messageRepository = MessageRepository();
  final MemberRepository _memberRepository = MemberRepository();
  final AuthRepository _authRepository = AuthRepository();
  final SocketIoService _socketService = SocketIoService();
  final LiveBroadcastRepository _broadcastRepository =
      LiveBroadcastRepository();

  final String _groupId = Config.liveStreamGroupId;
  Timer? _pollingTimer;
  Timer? _typingTimer;
  // ✅ Real "is this actually a live broadcast" status, from YouTube's own
  // Data API (see LiveBroadcastRepository) — separate from _isConnected
  // (chat socket) and _isPlayerInitialized (iframe loaded). Polled on the
  // same 30s cadence as the backend's own cache, so this never gets more
  // stale than the source of truth it's reading from. Starts `unknown`
  // rather than defaulting to "live", so a video is never claimed to be
  // broadcasting before the first real check comes back.
  Timer? _broadcastStatusTimer;
  YoutubeBroadcastStatus _broadcastStatus = YoutubeBroadcastStatus.unknown;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _memberSubscription;

  DateTime? _lastMessageTime;
  final Map<String, int> _userMessageCount = {};
  Set<int> _typingUsers = {};
  bool _isTyping = false;

  bool _isPlayerInitialized = false;
  bool _isLoading = true;
  bool _isConnected = false;
  String _errorMessage = '';
  // ✅ FIX: a video load failure used to write into _errorMessage, which
  // build() treats as "the whole screen failed" and replaces video + chat
  // + members with a single full-page error and one "Retry Connection"
  // button — even though chat/members had nothing wrong with them and
  // were often still fully usable. This flag scopes a video failure to
  // just the video player area instead (see _buildVideoPlayer below), so
  // a broken/blocked video doesn't take the rest of the live screen down
  // with it. _errorMessage is now reserved for genuine whole-screen init
  // failures (socket setup, initial data load) thrown from _initializeApp.
  bool _videoFailed = false;

  // ✅ Real broadcast status ('live' / 'upcoming' / 'none' / 'not_found' /
  // 'unknown'), fetched from the backend's YouTube Data API check — see
  // MessageRepository.fetchYoutubeLiveStatus and backend/api/v1/live.py.
  // Nothing in this screen previously asked YouTube whether the video was
  // actually broadcasting; it just loaded the iframe and assumed. This
  // drives the real "LIVE" badge in _buildLiveStatusBar, kept deliberately
  // separate from _isConnected (which only ever reflects chat socket
  // connectivity — see that fix above).
  String _youtubeStatus = 'unknown';
  Timer? _youtubeStatusTimer;

  // --- Permission-gated "Go Live" state (see backend/api/v1/broadcasts.py
  // and LiveBroadcastRepository) ---------------------------------------
  // Whether *this* user is allowed to start their own broadcast right now
  // (admin, or explicitly granted `can_go_live`). Drives whether the
  // "Go Live" action even appears — most viewers will never see it.
  bool _canGoLive = false;
  // This user's own currently-live broadcast, if any. Non-null flips the
  // AppBar action from "Go Live" to "End Live".
  LiveBroadcast? _myBroadcast;
  // Everyone who's currently live, on any platform (public GET
  // /live/broadcasts) — shown as a "Live now" strip so viewers can pick
  // whose stream to watch instead of always seeing the single hardcoded
  // Config.youTubeVideoId feed.
  List<LiveBroadcast> _liveBroadcasts = [];
  // Which broadcast is currently loaded in the main player. Null means
  // "the default/official stream" (the pre-existing Config.youTubeVideoId
  // behavior), so nothing about that fallback path changes for viewers who
  // never touch the new feature.
  LiveBroadcast? _activeSource;
  bool _isStartingBroadcast = false;
  Timer? _liveBroadcastsTimer;
  ChewieController? _chewieController;
  VideoPlayerController? _nativeVideoController;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Render the real screen on the very next frame. Everything below talks
    // to the network and fills in its own corner of the UI as data arrives
    // (chat via _handleIncomingMessages, members via _loadOnlineMembers,
    // connection badge via _handleConnectionStatus, video via
    // _isPlayerInitialized) — none of that needs to block first paint.
    // Previously this awaited the socket handshake and the initial data
    // fetch *before* flipping _isLoading, so a slow or flaky connection
    // left the whole screen showing nothing but a spinner.
    try {
      _initializePlayer();
    } catch (e) {
      debugPrint('❌ Error initializing player: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // Fire-and-forget: each of these already handles its own errors
    // internally (socket connect failure falls back to polling; data load
    // failure is caught and logged) so there's nothing to await here.
    unawaited(_initializeSocketConnection());
    unawaited(_loadInitialData());
    _startBroadcastStatusPolling();
    _startLiveBroadcastsPolling();
  }

  void _initializePlayer() {
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        mute: false,
        showFullscreenButton: true,
        loop: false,
        enableCaption: true,
        strictRelatedVideos: true,
        enableJavaScript: true,
      ),
    );

    _loadVideo();
  }

  Future<void> _loadVideo() async {
    if (mounted) setState(() => _videoFailed = false);
    try {
      await _controller.loadVideoById(videoId: Config.youTubeVideoId);
      if (mounted) {
        setState(() {
          _isPlayerInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading video: $e');
      if (mounted) {
        setState(() {
          _isPlayerInitialized = false;
          _videoFailed = true;
        });
      }
    }
  }

  Future<void> _initializeSocketConnection() async {
    if (!Config.enableLiveChat) {
      debugPrint('⚠️ Live chat disabled in configuration');
      return;
    }

    // ✅ FIX: cancel any existing subscriptions before creating new ones.
    // Without this, calling _retryConnection() (which re-runs
    // _initializeApp -> _initializeSocketConnection) silently stacks a new
    // set of listeners on top of the old ones instead of replacing them,
    // leaking a subscription on every retry.
    await _cancelSocketSubscriptions();

    try {
      await _socketService.initialize();

      final liveGroupId = int.tryParse(_groupId) ?? 1;

      _messageSubscription = _socketService.watchMessages(liveGroupId).listen((
        List<GroupMessage> messages,
      ) {
        _handleIncomingMessages(messages);
      });

      _typingSubscription = _socketService
          .watchTyping(liveGroupId)
          .listen(_handleTypingUpdate);

      _connectionSubscription = _socketService
          .watchConnectionStatus(liveGroupId)
          .listen(_handleConnectionStatus);

      _memberSubscription = _socketService
          .watchGroupMembers(liveGroupId)
          .listen(_handleMemberUpdates);

      debugPrint('✅ WebSocket connection initialized for live stream');
    } catch (e) {
      debugPrint('❌ WebSocket connection failed: $e');
      _startPollingFallback();
    }
  }

  Future<void> _cancelSocketSubscriptions() async {
    await _messageSubscription?.cancel();
    await _typingSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _memberSubscription?.cancel();
    _messageSubscription = null;
    _typingSubscription = null;
    _connectionSubscription = null;
    _memberSubscription = null;
  }

  void _handleIncomingMessages(List<GroupMessage> messages) {
    if (!mounted) return;

    setState(() {
      _messages.clear();
      _messages.addAll(
        messages.map(
          (groupMsg) => Message(
            id: groupMsg.id.toString(),
            content: groupMsg.content,
            senderId: groupMsg.senderId.toString(),
            timestamp: groupMsg.createdAt,
            messageType: groupMsg.messageType,
            senderName: groupMsg.sender?['name']?.toString() ?? 'User',
          ),
        ),
      );
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
    _scrollToBottom();
  }

  void _handleMemberUpdates(List<dynamic> memberData) {
    if (!mounted) return;

    setState(() {
      _members.clear();
      _members.addAll(memberData.map((data) => Member.fromJson(data)).toList());
    });
  }

  void _handleTypingUpdate(List<int> typingUserIds) {
    if (!mounted) return;

    setState(() {
      _typingUsers = typingUserIds.toSet();
    });
  }

  void _handleConnectionStatus(bool connected) {
    if (!mounted) return;

    setState(() {
      _isConnected = connected;
    });

    if (!connected) {
      _startPollingFallback();
    } else {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  Future<void> _loadInitialData() async {
    try {
      // ✅ USE LIVE STREAM MESSAGES, NOT GROUP MESSAGES
      if (!_isConnected) {
        final messages = await _messageRepository.fetchLiveMessages();
        if (mounted) {
          setState(() {
            // ✅ FIX: clear before adding. Previously this only ever
            // appended, so calling _initializeApp() a second time (e.g.
            // via the "Retry Connection" button) duplicated every message
            // already in the list.
            _messages.clear();
            _messages.addAll(messages);
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          });
        }
      }

      // ✅ REAL LIVE STREAM MEMBER LOADING
      await _loadOnlineMembers();
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    }
  }

  Future<void> _loadOnlineMembers() async {
    try {
      // ✅ USE LIVE STREAM SPECIFIC METHOD
      final realMembers = await _memberRepository.fetchLiveMembers();

      if (mounted) {
        setState(() {
          _members.clear();
          _members.addAll(realMembers);
        });
      }
    } catch (e) {
      debugPrint('Error loading live members: $e');
      if (mounted) {
        setState(() {
          _members.clear();
        });
      }
    }
  }

  void _sendMessage() async {
    if (!Config.enableLiveChat) {
      _showFeatureDisabledMessage();
      return;
    }

    final content = _messageController.text.trim();
    final validation = Validators.validateMessage(content);
    if (!validation.isValid) {
      _showErrorMessage(validation.errorMessage!);
      return;
    }

    if (!Validators.isWithinRateLimit(_lastMessageTime)) {
      _showErrorMessage('Please wait before sending another message');
      return;
    }

    if (Validators.isUserOverRateLimit(_userMessageCount)) {
      _showErrorMessage('Message rate limit exceeded. Please wait.');
      return;
    }

    try {
      if (_isConnected) {
        final user = await _authRepository.getCurrentUser();
        if (user == null) {
          // ✅ FIX: previously this silently dropped the message with no
          // feedback at all if the user came back null.
          _showErrorMessage(
            'Could not verify your account. Please log in again.',
          );
          return;
        }
        _socketService.sendMessage(int.tryParse(_groupId) ?? 1, {
          'groupId': _groupId,
          'content': content,
          'senderId': user.id,
        });
      } else {
        // ✅ USE LIVE STREAM MESSAGE SENDING
        final sentMessage = await _messageRepository.sendLiveMessage(content);
        if (sentMessage == null) {
          // ✅ FIX: previously a null result was silently ignored - the
          // input was already cleared below, so the message just vanished
          // with no indication anything went wrong.
          _showErrorMessage('Failed to send message. Please try again.');
          return;
        }
        if (mounted) {
          setState(() {
            _messages.add(sentMessage);
          });
        }
      }

      _lastMessageTime = DateTime.now();
      _updateUserMessageCount();
      _messageController.clear();
      _stopTyping();
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error sending live message: $e');
      _showErrorMessage('Failed to send message. Please try again.');
    }
  }

  void _updateUserMessageCount() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _userMessageCount[now.toString()] = now;

    if (_userMessageCount.length > Config.maxMessagesPerMinute) {
      final oldestKey = _userMessageCount.keys.first;
      _userMessageCount.remove(oldestKey);
    }
  }

  void _startTyping() {
    if (!_isTyping && _isConnected) {
      _isTyping = true;
      _socketService.sendTyping(int.tryParse(_groupId) ?? 1, true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
    }
  }

  void _stopTyping() {
    if (_isTyping && _isConnected) {
      _isTyping = false;
      _socketService.sendTyping(int.tryParse(_groupId) ?? 1, false);
    }
    _typingTimer?.cancel();
  }

  void _startPollingFallback() {
    // ✅ FIX: cancel any existing timer first. Both _handleConnectionStatus
    // and the catch-block in _initializeSocketConnection can call this;
    // without the guard, a flaky connection could end up with multiple
    // overlapping periodic timers all polling the network simultaneously.
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      Duration(seconds: Config.messagePollingInterval),
      (_) {
        if (mounted) _fetchNewMessages();
      },
    );
  }

  // Kicks off (and re-fires on a timer) the real YouTube broadcast-status
  // check — see LiveBroadcastRepository. 30s matches the backend's own
  // cache window (see api/v1/live.py's @cache.cached(timeout=30)), so
  // this never polls faster than the answer can actually change.
  void _startBroadcastStatusPolling() {
    _broadcastStatusTimer?.cancel();
    _checkBroadcastStatus();
    _broadcastStatusTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkBroadcastStatus(),
    );
  }

  Future<void> _checkBroadcastStatus() async {
    final info = await _broadcastRepository.fetchBroadcastStatus(
      videoId: Config.youTubeVideoId,
    );
    if (!mounted) return;
    setState(() => _broadcastStatus = info.status);
  }

  // --- Go-live permission + broadcast list -----------------------------

  void _startLiveBroadcastsPolling() {
    _liveBroadcastsTimer?.cancel();
    _refreshGoLiveState();
    _liveBroadcastsTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshGoLiveState(),
    );
  }

  Future<void> _refreshGoLiveState() async {
    try {
      final results = await Future.wait([
        _broadcastRepository.canGoLive(),
        _broadcastRepository.listLiveBroadcasts(),
        _broadcastRepository.myBroadcasts(),
      ]);
      if (!mounted) return;

      final canGoLive = results[0] as bool;
      final liveBroadcasts = results[1] as List<LiveBroadcast>;
      final mine = results[2] as List<LiveBroadcast>;
      LiveBroadcast? myActive;
      for (final b in mine) {
        if (b.isLive) {
          myActive = b;
          break;
        }
      }

      setState(() {
        _canGoLive = canGoLive;
        _liveBroadcasts = liveBroadcasts;
        _myBroadcast = myActive;
        // If the broadcast we were watching just ended (or was removed),
        // fall back to the default stream rather than staring at a dead
        // player with no indication anything changed.
        if (_activeSource != null &&
            !liveBroadcasts.any((b) => b.id == _activeSource!.id)) {
          _activeSource = null;
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error refreshing go-live state: $e');
      // Non-fatal: leave whatever state we already have in place.
    }
  }

  /// Entry point for the AppBar's "go live" button. Doesn't just hide the
  /// option for users without permission — it explains why, so someone
  /// who thinks they should have access has something actionable to act
  /// on (ask an admin) instead of a button that's mysteriously missing.
  Future<void> _onGoLivePressed() async {
    if (!_canGoLive) {
      await _showNoPermissionDialog();
      return;
    }
    await _showGoLiveSheet();
  }

  Future<void> _showNoPermissionDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded),
        title: const Text("You don't have permission yet"),
        content: const Text(
          "You don't currently have permission to start a live broadcast. "
          'Ask an admin to grant you access from your profile.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGoLiveSheet() async {
    LiveBroadcastPlatform platform = LiveBroadcastPlatform.youtube;
    final titleController = TextEditingController();
    final streamRefController = TextEditingController();

    final started = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Go Live',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<LiveBroadcastPlatform>(
                      segments: const [
                        ButtonSegment(
                          value: LiveBroadcastPlatform.youtube,
                          label: Text('YouTube'),
                        ),
                        ButtonSegment(
                          value: LiveBroadcastPlatform.facebook,
                          label: Text('Facebook'),
                        ),
                        ButtonSegment(
                          value: LiveBroadcastPlatform.native,
                          label: Text('In-app'),
                        ),
                      ],
                      selected: {platform},
                      onSelectionChanged: (selection) {
                        setSheetState(() => platform = selection.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (platform != LiveBroadcastPlatform.native) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: streamRefController,
                        decoration: InputDecoration(
                          labelText: platform == LiveBroadcastPlatform.youtube
                              ? 'YouTube video ID'
                              : 'Facebook video URL',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        "We'll give you an RTMP URL and stream key to plug "
                        'into your broadcasting app (e.g. OBS). You\'ll go '
                        "live as soon as it starts receiving your video.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isStartingBroadcast
                            ? null
                            : () async {
                                if (platform != LiveBroadcastPlatform.native &&
                                    streamRefController.text.trim().isEmpty) {
                                  _showErrorMessage(
                                    platform == LiveBroadcastPlatform.youtube
                                        ? 'Enter a YouTube video ID'
                                        : 'Enter a Facebook video URL',
                                  );
                                  return;
                                }
                                setSheetState(
                                  () => _isStartingBroadcast = true,
                                );
                                final ok = await _startBroadcast(
                                  platform: platform,
                                  title: titleController.text,
                                  streamRef: streamRefController.text,
                                );
                                setSheetState(
                                  () => _isStartingBroadcast = false,
                                );
                                if (ok && mounted) {
                                  Navigator.of(sheetContext).pop(true);
                                }
                              },
                        child: _isStartingBroadcast
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text('Start broadcast'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    streamRefController.dispose();

    if (started == true) {
      _showErrorMessage('You are now live!');
    }
  }

  /// Returns true on success. Errors are surfaced via a snackbar rather
  /// than thrown, since this is called from sheet UI that just needs a
  /// yes/no to decide whether to close.
  Future<bool> _startBroadcast({
    required LiveBroadcastPlatform platform,
    required String title,
    required String streamRef,
  }) async {
    try {
      final broadcast = await _broadcastRepository.startBroadcast(
        platform: platform,
        title: title.trim().isEmpty ? null : title.trim(),
        streamRef: platform == LiveBroadcastPlatform.native
            ? null
            : streamRef.trim(),
      );

      if (!mounted) return true;

      setState(() {
        _myBroadcast = broadcast;
        if (broadcast.isLive) {
          _activeSource = broadcast;
        }
      });

      if (broadcast.platform == LiveBroadcastPlatform.native) {
        await _showNativeStreamDetails(broadcast);
      }

      await _refreshGoLiveState();
      return true;
    } catch (e) {
      debugPrint('❌ Error starting broadcast: $e');
      _showErrorMessage(
        "Couldn't start your broadcast. ${_permissionAwareError(e)}",
      );
      return false;
    }
  }

  String _permissionAwareError(Object e) {
    final message = e.toString();
    if (message.contains('403')) {
      return "You don't have permission to go live.";
    }
    if (message.contains('503')) {
      return 'In-app streaming is not configured on the server yet.';
    }
    return 'Please try again.';
  }

  Future<void> _showNativeStreamDetails(LiveBroadcast broadcast) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your stream details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter these into your broadcasting app (e.g. OBS, Larix '
              'Broadcaster). You\'ll appear live once it starts receiving '
              'video.',
            ),
            const SizedBox(height: 16),
            _CopyableField(
              label: 'Server / RTMP URL',
              value: broadcast.rtmpUrl ?? '',
            ),
            const SizedBox(height: 8),
            _CopyableField(
              label: 'Stream key',
              value: broadcast.rtmpStreamKey ?? '',
              obscure: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _endMyBroadcast() async {
    final broadcast = _myBroadcast;
    if (broadcast == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End your broadcast?'),
        content: Text(
          'This will end "${broadcast.title}" for everyone watching.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End broadcast'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _broadcastRepository.endBroadcast(broadcast.id);
      if (!mounted) return;
      setState(() {
        if (_activeSource?.id == broadcast.id) {
          _activeSource = null;
        }
        _myBroadcast = null;
      });
      await _refreshGoLiveState();
    } catch (e) {
      debugPrint('❌ Error ending broadcast: $e');
      _showErrorMessage("Couldn't end your broadcast. Please try again.");
    }
  }

  /// Switches the main player between the default stream (source == null)
  /// and someone's live broadcast.
  Future<void> _selectBroadcastSource(LiveBroadcast? source) async {
    if (_activeSource?.id == source?.id) return;
    setState(() => _activeSource = source);

    _disposeNativePlayer();

    if (source == null) {
      await _loadVideo();
      return;
    }

    switch (source.platform) {
      case LiveBroadcastPlatform.youtube:
        if (mounted) setState(() => _videoFailed = false);
        try {
          await _controller.loadVideoById(videoId: source.streamRef ?? '');
          if (mounted) setState(() => _isPlayerInitialized = true);
        } catch (e) {
          debugPrint('Error loading broadcast video: $e');
          if (mounted) {
            setState(() {
              _isPlayerInitialized = false;
              _videoFailed = true;
            });
          }
        }
        break;
      case LiveBroadcastPlatform.facebook:
        // No in-app embed player is wired up for Facebook (that needs a
        // WebView package this app doesn't currently depend on) — open the
        // public video URL in the browser/Facebook app instead.
        final url = source.streamRef;
        if (url != null && url.isNotEmpty) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        break;
      case LiveBroadcastPlatform.native:
        await _initNativePlayer(source);
        break;
    }
  }

  Future<void> _initNativePlayer(LiveBroadcast source) async {
    final url = source.hlsPlaybackUrl;
    if (url == null) return;
    try {
      final videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      await videoController.initialize();
      final chewie = ChewieController(
        videoPlayerController: videoController,
        autoPlay: true,
        looping: false,
      );
      if (!mounted) {
        chewie.dispose();
        videoController.dispose();
        return;
      }
      setState(() {
        _nativeVideoController = videoController;
        _chewieController = chewie;
      });
    } catch (e) {
      debugPrint('Error initializing native stream player: $e');
      if (mounted) _showErrorMessage("Couldn't load that stream.");
    }
  }

  void _disposeNativePlayer() {
    _chewieController?.dispose();
    _chewieController = null;
    _nativeVideoController?.dispose();
    _nativeVideoController = null;
  }

  Future<void> _fetchNewMessages() async {
    if (!mounted) return;

    try {
      // ✅ USE LIVE STREAM MESSAGES ENDPOINT
      final messages = await _messageRepository.fetchLiveMessages();
      if (!mounted) return;

      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error fetching live messages: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorMessage(String message) {
    // ✅ FIX: guard against calling ScaffoldMessenger after the widget has
    // been disposed (e.g. an in-flight async call resolving after the user
    // has already navigated away).
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showFeatureDisabledMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Live chat is currently disabled'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _retryConnection() async {
    setState(() {
      _errorMessage = '';
    });
    await _initializeApp();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _broadcastStatusTimer?.cancel();
    _typingTimer?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _connectionSubscription?.cancel();
    _memberSubscription?.cancel();
    _socketService.disposeGroup(int.tryParse(_groupId) ?? 1);
    _controller.close();
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width >= 1200;
    final isMediumScreen = screenSize.width >= 768;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Service')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Service')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _retryConnection,
                  child: const Text('Retry Connection'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Service'),
        actions: [
          Tooltip(
            message: _isConnected
                ? 'Chat connected'
                : 'Chat reconnecting — video is unaffected',
            child: Icon(
              _isConnected ? Icons.wifi : Icons.wifi_off,
              color: _isConnected ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload video',
            onPressed: _loadVideo,
          ),
          // Always visible — tapping it either opens the go-live flow (if
          // the user is admin or has been explicitly granted permission,
          // see _refreshGoLiveState/_canGoLive), ends their current
          // broadcast if they're already live, or explains why they can't
          // go live yet rather than the option just silently not being
          // there.
          _myBroadcast != null
              ? IconButton(
                  icon: const Icon(Icons.stop_circle_outlined),
                  color: Colors.red,
                  tooltip: 'End your broadcast',
                  onPressed: _endMyBroadcast,
                )
              : IconButton(
                  icon: const Icon(Icons.videocam_outlined),
                  tooltip: 'Go live',
                  onPressed: _onGoLivePressed,
                ),
        ],
      ),
      body: isLargeScreen
          ? _buildDesktopLayout(theme, screenSize)
          : isMediumScreen
          ? _buildTabletLayout(theme, screenSize)
          : _buildMobileLayout(theme, screenSize),
    );
  }

  Widget _buildLiveStatusBar(ThemeData theme) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          // ✅ FIX: this used to read "LIVE NOW" / "CONNECTING..." driven
          // by _isConnected — but _isConnected only tracks the *chat
          // socket*, not the YouTube stream itself (see
          // _handleConnectionStatus). A user whose video was playing
          // perfectly fine but whose chat socket briefly dropped would
          // see this flip to grey "CONNECTING...", reading as if the
          // broadcast had gone down. This now labels what it actually
          // reflects — chat connectivity — while the polling fallback
          // (_startPollingFallback) keeps chat itself working either way.
          Icon(
            _isConnected ? Icons.circle : Icons.circle_outlined,
            color: _isConnected ? Colors.green : Colors.orange,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isConnected ? 'Chat connected' : 'Reconnecting chat…',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _isConnected
                    ? theme.colorScheme.onSurface
                    : Colors.orange,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _members.isEmpty ? '' : '${_members.length} watching',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          Positioned.fill(child: _buildVideoPlayerContent()),
          // ✅ This badge is the actual fix for the "app always looks
          // live regardless of reality" gap — it's driven by
          // _broadcastStatus (YouTube's own liveBroadcastContent field,
          // see LiveBroadcastRepository), not by whether the iframe
          // merely loaded. Hidden entirely while the video itself is
          // broken, and hidden for `unknown`/`none` too — a badge that
          // can only ever say "maybe" isn't worth showing.
          if (!_videoFailed)
            Positioned(top: 12, left: 12, child: _buildBroadcastBadge()),
        ],
      ),
    );
  }

  Widget _buildBroadcastBadge() {
    return switch (_broadcastStatus) {
      YoutubeBroadcastStatus.live => _buildStatusPill(
        label: 'LIVE',
        color: Colors.red,
        showDot: true,
      ),
      YoutubeBroadcastStatus.upcoming => _buildStatusPill(
        label: 'Starting soon',
        color: Colors.amber.shade800,
      ),
      YoutubeBroadcastStatus.none ||
      YoutubeBroadcastStatus.notFound ||
      YoutubeBroadcastStatus.unknown => const SizedBox.shrink(),
    };
  }

  Widget _buildStatusPill({
    required String label,
    required Color color,
    bool showDot = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayerContent() {
    if (_activeSource?.platform == LiveBroadcastPlatform.native) {
      final chewie = _chewieController;
      if (chewie == null) {
        // _initNativePlayer hasn't finished (or failed silently) yet.
        return Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
            ),
          ),
        );
      }
      return Chewie(controller: chewie);
    }

    if (_videoFailed) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.videocam_off_outlined,
                  color: Colors.white70,
                  size: 40,
                ),
                const SizedBox(height: 12),
                const Text(
                  "Couldn't load the video",
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  onPressed: _loadVideo,
                  child: const Text('Retry video'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ✅ FIX: previously this widget was only mounted once
    // `_isPlayerInitialized` was true — but that flag only ever became
    // true *after* `_controller.loadVideoById()` resolved, and
    // `loadVideoById()` can only actually load a video into an iframe
    // that this very widget is responsible for creating in the first
    // place. That's a deadlock: the widget that creates the platform
    // view/iframe never mounted, because it was waiting on a flag that
    // could only flip once that same widget had already loaded a video.
    // The visible symptom was an infinite spinner with no iframe ever
    // appearing in the DOM. `YoutubePlayer` handles its own internal
    // loading UI, so it's safe (and necessary) to mount it unconditionally
    // as soon as the controller exists. `_isPlayerInitialized` is kept
    // only as bookkeeping for other logic — it no longer gates the widget.
    return YoutubePlayer(controller: _controller);
  }

  Widget _buildTabbedPanel(ThemeData theme) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: TabBar(
              tabs: const [
                Tab(text: 'Chat'),
                Tab(text: 'Members'),
              ],
              indicatorColor: theme.colorScheme.primary,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurface.withAlpha(153),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [_buildChatTab(theme), _buildMembersTab(theme)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(ThemeData theme, Size screenSize) {
    return Column(
      children: [
        _buildVideoPlayer(),
        _buildLiveStatusBar(theme),
        const Divider(height: 1),
        Expanded(child: _buildTabbedPanel(theme)),
      ],
    );
  }

  Widget _buildTabletLayout(ThemeData theme, Size screenSize) {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Expanded(flex: 3, child: _buildVideoPlayer()),
              _buildLiveStatusBar(theme),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.dividerColor)),
            ),
            // ✅ FIX: tablet layout previously showed only the chat tab,
            // with no way at all to view the members list on a
            // tablet-sized screen. Now uses the same tabbed panel as
            // mobile and desktop.
            child: _buildTabbedPanel(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(ThemeData theme, Size screenSize) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 7,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: screenSize.width * 0.7,
                      maxHeight: screenSize.height * 0.8,
                    ),
                    child: _buildVideoPlayer(),
                  ),
                ),
              ),
              _buildLiveStatusBar(theme),
            ],
          ),
        ),
        SizedBox(width: 400, child: _buildTabbedPanel(theme)),
      ],
    );
  }

  Widget _buildChatTab(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                        Text(
                          'Be the first to chat!',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _buildMessageBubble(msg, theme);
                    },
                  ),
          ),

          if (_typingUsers.isNotEmpty) ...[
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_typingUsers.length} user${_typingUsers.length > 1 ? 's' : ''} typing...',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],

          Container(
            height: 70,
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.trim().isNotEmpty) {
                        _startTyping();
                      } else {
                        _stopTyping();
                      }
                    },
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => openUserProfile(context, int.tryParse(msg.senderId)),
            child: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withAlpha(25),
              child: Icon(
                Icons.person,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.senderName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(msg.content, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  _formatTime(msg.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(128),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab(ThemeData theme) {
    return _members.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('No members online', style: TextStyle(color: Colors.grey)),
                Text(
                  'Members will appear when they join',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              return ListTile(
                leading: GestureDetector(
                  onTap: () =>
                      openUserProfile(context, int.tryParse(member.id)),
                  child: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withAlpha(25),
                    child: Icon(
                      Icons.person,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                ),
                title: Text(member.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  member.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: member.isOnline ? Colors.green : Colors.grey,
                  ),
                ),
              );
            },
          );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

/// A labeled read-only field with a button to copy its value to the
/// clipboard. Used to display RTMP server URL / stream key details.
class _CopyableField extends StatelessWidget {
  const _CopyableField({
    required this.label,
    required this.value,
    this.obscure = false,
  });

  final String label;
  final String value;
  final bool obscure;

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = obscure && value.isNotEmpty
        ? '•' * value.length
        : (value.isEmpty ? '—' : value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayValue,
                  style: const TextStyle(fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy',
                onPressed: value.isEmpty
                    ? null
                    : () => _copyToClipboard(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
