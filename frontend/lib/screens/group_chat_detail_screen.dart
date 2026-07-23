// lib/screens/group_chat_detail_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pensaconnect/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:pensaconnect/services/auth_service.dart';
import '../repositories/group_chat_repository.dart';
import '../repositories/user_repository.dart';
import '../models/group_message_model.dart';
import '../services/socketio_service.dart';
import '../utils/profile_navigation.dart';

class GroupChatDetailScreen extends StatefulWidget {
  final int groupId;
  final String groupName;

  const GroupChatDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatDetailScreen> createState() => _GroupChatDetailScreenState();
}

class _GroupChatDetailScreenState extends State<GroupChatDetailScreen> {
  late GroupChatRepository _groupRepo;
  late SocketIoService _socketService;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<GroupMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _isConnected = false;
  bool _isTyping = false;
  bool _initialLoadDone = false;
  Timer? _typingTimer;
  StreamSubscription<List<GroupMessage>>? _messageSubscription;

  // Keyed by user id. Populated once from the group's member list and used
  // as a fallback whenever a message arrives with missing/partial sender
  // info (e.g. a Socket.IO payload that only carried a bare senderId) —
  // this is what previously showed up as "Unknown User" with no picture
  // in the chat until the next full reload.
  final Map<int, Map<String, dynamic>> _memberInfo = {};

  // ✅ FIX: track whether auth has genuinely timed out, so the screen can
  // recover instead of spinning on "Authenticating..." forever if a user
  // really isn't logged in (e.g. expired session).
  Timer? _authTimeoutTimer;
  bool _authTimedOut = false;
  static const _authTimeout = Duration(seconds: 8);

  // ✅ LIVE getter instead of stale field
  int? get _currentUserId {
    final authService = AuthService();
    return authService.userId;
  }

  bool get _isAuthenticated => _currentUserId != null && _currentUserId! > 0;

  // ✅ Auth listener for rebuilds
  late final VoidCallback _authListener;
  bool _hasJoinedRoom = false;

  @override
  void initState() {
    super.initState();

    // ✅ Listen to AuthService changes
    _authListener = _onAuthChanged;
    AuthService().addListener(_authListener);

    _startAuthTimeoutWatch();
    _initialize();
  }

  void _startAuthTimeoutWatch() {
    _authTimeoutTimer?.cancel();
    if (_isAuthenticated) return;

    _authTimeoutTimer = Timer(_authTimeout, () {
      if (!mounted || _isAuthenticated) return;
      setState(() => _authTimedOut = true);
    });
  }

  void _onAuthChanged() {
    if (!mounted) return;

    debugPrint('🔄 Auth state changed, current user ID: $_currentUserId');

    if (_isAuthenticated) {
      _authTimeoutTimer?.cancel();
      _authTimedOut = false;
    }

    setState(() {});

    // ✅ If we now have a user and haven't joined, join the room
    if (_isAuthenticated && !_hasJoinedRoom) {
      _joinSocketRoom();
    }
  }

  Future<void> _initialize() async {
    // ✅ Get services from context
    _groupRepo = context.read<GroupChatRepository>();
    _socketService = context.read<SocketIoService>();

    debugPrint('👤 GroupChatDetail: Current User ID = $_currentUserId');

    if (!_isAuthenticated) {
      debugPrint('⚠️ Warning: User ID is null or 0! Trying to refresh...');
      final authService = AuthService();
      await authService.refreshUser();
      debugPrint('🔄 After refresh: User ID = $_currentUserId');
    }

    // ✅ Initialize socket service
    try {
      await _socketService.initialize();
      debugPrint('✅ SocketIoService initialized');
      _socketService.debugConnectionStatus(widget.groupId);
    } catch (e) {
      debugPrint('❌ SocketIoService init error: $e');
    }

    // ✅ Start listening BEFORE loading messages
    _setupRealtimeListener();

    // Fire-and-forget: doesn't block messages from showing, just backfills
    // names/avatars for any message whose own sender data turns out thin.
    _loadMemberInfo();

    // ✅ Load messages
    await _loadInitialMessages();

    // ✅ Join WebSocket room
    _joinSocketRoom();

    // Setup typing detection
    _setupTypingDetection();
  }

  Future<void> _retryAuth() async {
    setState(() => _authTimedOut = false);
    _startAuthTimeoutWatch();
    await AuthService().refreshUser();
    if (_isAuthenticated) {
      _joinSocketRoom();
    } else if (mounted) {
      setState(() => _authTimedOut = true);
    }
  }

  void _joinSocketRoom() {
    // ✅ Live auth check
    if (!_isAuthenticated) {
      debugPrint(
        '⚠️ Cannot join room: No user ID available (ID: $_currentUserId)',
      );
      return;
    }

    if (_hasJoinedRoom) {
      debugPrint('🔄 Already joined room ${widget.groupId}');
      return;
    }

    try {
      debugPrint(
        '🚀 Joining WebSocket room for group ${widget.groupId} with user ID: $_currentUserId',
      );
      _socketService.debugConnectionStatus(widget.groupId);

      setState(() {
        _isConnected = _socketService.isConnected(widget.groupId);
        _hasJoinedRoom = true;
      });

      debugPrint('✅ Successfully joined room ${widget.groupId}');
    } catch (e) {
      debugPrint('⚠️ Error joining socket room: $e');
    }
  }

  Future<void> _loadInitialMessages() async {
    if (_initialLoadDone) {
      debugPrint('📦 Messages already loaded, skipping...');
      return;
    }

    try {
      debugPrint('📥 Loading initial messages for group ${widget.groupId}...');
      final messages = await _groupRepo.getMessages(widget.groupId);

      if (mounted) {
        setState(() {
          _messages = messages;
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _loading = false;
          _initialLoadDone = true;
        });
        debugPrint('✅ Loaded ${_messages.length} messages');
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('❌ Error loading initial messages: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMemberInfo() async {
    try {
      final members = await _groupRepo.getGroupMembers(widget.groupId);
      if (!mounted) return;
      setState(() {
        for (final m in members) {
          if (m.user != null) _memberInfo[m.userId] = m.user!;
        }
      });
    } catch (e) {
      debugPrint('⚠️ Could not load group members for sender fallback: $e');
    }
  }

  void _setupRealtimeListener() {
    _messageSubscription?.cancel();

    _messageSubscription = _groupRepo
        .watchMessages(widget.groupId)
        .listen(
          (newMessages) {
            if (!mounted) return;

            debugPrint('📨 Received real-time update');

            setState(() {
              final cached = _socketService.getCachedMessages(widget.groupId);
              if (cached != null && cached.isNotEmpty) {
                _messages = List.from(cached);
                _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                _isConnected = _socketService.isConnected(widget.groupId);
                debugPrint(
                  '✅ Updated from cache: ${_messages.length} messages',
                );
              } else {
                for (final msg in newMessages) {
                  if (!_messages.any((m) => m.id == msg.id)) {
                    _messages.add(msg);
                  }
                }
                _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                _isConnected = true;
                debugPrint('✅ Merged messages: ${_messages.length} total');
              }
            });
            _scrollToBottom();
          },
          onError: (error) {
            debugPrint('❌ Real-time message error: $error');
            if (mounted) {
              setState(() {
                _isConnected = false;
              });
            }
          },
        );
  }

  void _setupTypingDetection() {
    _controller.addListener(() {
      _typingTimer?.cancel();

      // ✅ Live auth check
      if (_isAuthenticated) {
        _socketService.sendTyping(widget.groupId, true);
      } else {
        debugPrint('⚠️ Skipping typing indicator: No user ID');
      }

      if (mounted) {
        setState(() {
          _isTyping = _controller.text.trim().isNotEmpty;
        });
      }

      _typingTimer = Timer(const Duration(seconds: 2), () {
        // ✅ Live auth check
        if (_isAuthenticated) {
          _socketService.sendTyping(widget.groupId, false);
        }
        if (mounted) {
          setState(() {
            _isTyping = false;
          });
        }
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // ✅ Live auth check before sending
    if (!_isAuthenticated) {
      debugPrint(
        '❌ Cannot send message: User ID not available (ID: $_currentUserId)',
      );

      try {
        final authService = AuthService();
        await authService.refreshUser();
        if (!_isAuthenticated) {
          debugPrint('❌ Still not authenticated after refresh');
          _showAuthError();
          return;
        }
      } catch (e) {
        debugPrint('❌ Auth refresh failed: $e');
        _showAuthError();
        return;
      }
    }

    setState(() => _sending = true);

    try {
      _typingTimer?.cancel();

      if (_isAuthenticated) {
        _socketService.sendTyping(widget.groupId, false);
      }

      debugPrint('📤 Sending message with user ID: $_currentUserId');
      await _groupRepo.sendMessage(groupId: widget.groupId, content: text);

      _controller.clear();
      setState(() => _isTyping = false);
      debugPrint('✅ Message sent successfully');
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                _controller.text = text;
                _sendMessage();
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _showAuthError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Authentication error. Please log in again.'),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  bool _isNewDay(int index) {
    if (index == 0) return true;
    final prev = _messages[index - 1].createdAt;
    final curr = _messages[index].createdAt;
    return prev.year != curr.year ||
        prev.month != curr.month ||
        prev.day != curr.day;
  }

  bool _isGroupedWithPrevious(int index) {
    if (index == 0) return false;
    if (_isNewDay(index)) return false;
    final prev = _messages[index - 1];
    final curr = _messages[index];
    final sameSender = prev.senderId == curr.senderId;
    final closeInTime = curr.createdAt.difference(prev.createdAt).inMinutes < 3;
    return sameSender && closeInTime;
  }

  bool _isGroupedWithNext(int index) {
    if (index >= _messages.length - 1) return false;
    final curr = _messages[index];
    final next = _messages[index + 1];
    if (next.createdAt.day != curr.createdAt.day) return false;
    final sameSender = curr.senderId == next.senderId;
    final closeInTime = next.createdAt.difference(curr.createdAt).inMinutes < 3;
    return sameSender && closeInTime;
  }

  Widget _buildDateDivider(DateTime date) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String label;
    if (target == today) {
      label = 'Today';
    } else if (target == yesterday) {
      label = 'Yesterday';
    } else if (today.difference(target).inDays < 7) {
      label = DateFormat('EEEE').format(date);
    } else {
      label = DateFormat('MMM d, y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.dividerColor.withOpacity(0.4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: theme.dividerColor.withOpacity(0.4))),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(GroupMessage message, int index) {
    final isMe = message.senderId == _currentUserId;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final groupedWithPrev = _isGroupedWithPrevious(index);
    final groupedWithNext = _isGroupedWithNext(index);

    // Prefer the sender info carried on the message itself, but fall back
    // to the group member list whenever it's missing a name or picture
    // (e.g. a thin real-time payload) so people aren't shown as
    // "Unknown User" just because of where the message came from.
    final senderInfo = message.sender ?? _memberInfo[message.senderId];
    final fallbackInfo = _memberInfo[message.senderId];
    final profilePictureUrl =
        _getProfilePictureUrl(senderInfo) ??
        _getProfilePictureUrl(fallbackInfo);
    final fullName =
        senderInfo?['full_name'] ??
        senderInfo?['username'] ??
        fallbackInfo?['full_name'] ??
        fallbackInfo?['username'] ??
        'Unknown User';

    final messageLength = message.content.length;
    final isVeryShort = messageLength < 10;

    return Padding(
      padding: EdgeInsets.only(top: groupedWithPrev ? 2 : 10, bottom: 2),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            SizedBox(
              width: 32,
              child: groupedWithNext
                  ? null
                  : _buildAvatar(
                      profilePictureUrl,
                      fullName,
                      radius: 16,
                      userId: message.senderId,
                    ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe && !groupedWithPrev)
                  Padding(
                    padding: const EdgeInsets.only(left: 14, bottom: 3),
                    child: GestureDetector(
                      onTap: () => openUserProfile(
                        context,
                        message.senderId,
                        knownUsername: fullName,
                        knownProfilePicture: profilePictureUrl,
                      ),
                      child: Text(
                        fullName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary.withOpacity(0.85),
                        ),
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: isVeryShort
                        ? double.infinity
                        : MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: _bubbleRadius(
                      isMe,
                      groupedWithPrev,
                      groupedWithNext,
                    ),
                    color: isMe ? null : colorScheme.surfaceContainerHighest,
                    gradient: isMe
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colorScheme.primary,
                              colorScheme.primary.withOpacity(0.88),
                            ],
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isMe ? Colors.white : colorScheme.onSurface,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatModernTime(message.createdAt),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isMe
                                  ? Colors.white.withOpacity(0.75)
                                  : colorScheme.onSurface.withOpacity(0.45),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _buildMessageStatus(message),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  BorderRadius _bubbleRadius(
    bool isMe,
    bool groupedWithPrev,
    bool groupedWithNext,
  ) {
    const big = Radius.circular(18);
    const small = Radius.circular(5);

    if (isMe) {
      return BorderRadius.only(
        topLeft: big,
        bottomLeft: big,
        topRight: groupedWithPrev ? small : big,
        bottomRight: groupedWithNext ? small : big,
      );
    }
    return BorderRadius.only(
      topRight: big,
      bottomRight: big,
      topLeft: groupedWithPrev ? small : big,
      bottomLeft: groupedWithNext ? small : big,
    );
  }

  Widget _buildAvatar(
    String? url,
    String fullName, {
    double radius = 16,
    int? userId,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatar = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: (url != null && url.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth:
                    (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                memCacheHeight:
                    (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                errorWidget: (_, __, ___) =>
                    _buildFallbackAvatar(colorScheme, fullName),
              )
            : _buildFallbackAvatar(colorScheme, fullName),
      ),
    );

    // Tapping a message avatar opens that person's profile — same behavior
    // as every other avatar in the app (see widgets/user_avatar.dart).
    if (userId == null) return avatar;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfile(
        context,
        userId,
        knownUsername: fullName,
        knownProfilePicture: url,
      ),
      child: avatar,
    );
  }

  Widget _buildFallbackAvatar(ColorScheme colorScheme, String fullName) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _getInitials(fullName),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageStatus(GroupMessage message) {
    final colorScheme = Theme.of(context).colorScheme;

    if (message.readBy.length > 1) {
      return Icon(
        Icons.done_all_rounded,
        size: 13,
        color: Colors.white.withOpacity(0.9),
      );
    } else if (message.readBy.isNotEmpty) {
      return Icon(
        Icons.done_all_rounded,
        size: 13,
        color: colorScheme.secondary.withOpacity(0.9),
      );
    }
    return Icon(
      Icons.done_rounded,
      size: 13,
      color: Colors.white.withOpacity(0.65),
    );
  }

  String _formatModernTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime).toLowerCase();
  }

  String? _getProfilePictureUrl(Map<String, dynamic>? sender) {
    if (sender == null) return null;

    final profilePicture =
        sender['profile_picture'] ??
        sender['profilePicture'] ??
        sender['avatar'] ??
        sender['profile_image'] ??
        sender['senderProfilePicture'];

    if (profilePicture == null || profilePicture.toString().isEmpty) {
      return null;
    }

    final profilePictureStr = profilePicture.toString();

    if (profilePictureStr.startsWith('http://') ||
        profilePictureStr.startsWith('https://')) {
      return profilePictureStr;
    }

    // ✅ Route through the same env-aware helper the rest of the app uses,
    // instead of a hardcoded production host that silently breaks avatars
    // on any other environment (local/staging).
    return UserRepository.getProfilePictureUrl(profilePictureStr);
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Widget _buildConnectionStatus() {
    final theme = Theme.of(context);
    final color = _isConnected
        ? const Color(0xFF22C55E)
        : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            _isConnected ? 'Live' : 'Connecting',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    final hasText = _controller.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 46,
                  maxHeight: 120,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    if (hasText)
                      Padding(
                        padding: const EdgeInsets.only(right: 2, bottom: 2),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _isTyping = false);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _sending
                  ? Container(
                      key: const ValueKey('sending'),
                      width: 46,
                      height: 46,
                      padding: const EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(
                          theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : SizedBox(
                      key: const ValueKey('send'),
                      width: 46,
                      height: 46,
                      child: Material(
                        color: hasText
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withOpacity(0.4),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: hasText ? _sendMessage : null,
                          child: const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
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
                Icons.chat_bubble_outline_rounded,
                size: 32,
                color: theme.colorScheme.primary.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Say hello to ${widget.groupName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthGate(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.groupName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _authTimedOut
                ? [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 40,
                      color: theme.colorScheme.error.withOpacity(0.7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Couldn't verify your session",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Check your connection and try again.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _retryAuth,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        context.read<AuthProvider>().logout();
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                      child: const Text('Log in again'),
                    ),
                  ]
                : [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Authenticating…', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Please wait while we verify your session',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _typingTimer?.cancel();
    _authTimeoutTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();

    AuthService().removeListener(_authListener);

    _socketService.disposeGroup(widget.groupId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isAuthenticated) {
      return _buildAuthGate(theme);
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _buildAvatar(null, widget.groupName, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.groupName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${_messages.length} message${_messages.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _buildConnectionStatus(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh messages',
            onPressed: () async {
              setState(() => _loading = true);
              _initialLoadDone = false;
              await _loadInitialMessages();
              if (mounted) setState(() => _loading = false);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? _buildEmptyState(theme)
                : RefreshIndicator(
                    onRefresh: () async {
                      _initialLoadDone = false;
                      await _loadInitialMessages();
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final showDivider = _isNewDay(index);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showDivider)
                              _buildDateDivider(message.createdAt),
                            _buildMessageBubble(message, index),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }
}
