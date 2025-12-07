import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pensaconnect/models/group_message_model.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/member.dart';
import '../models/message_model.dart';
import '../repositories/message_repository.dart';
import '../repositories/member_repository.dart';
import '../repositories/auth_repository.dart';
import '../services/socketio_service.dart';
import '../config/config.dart';
import '../utils/validators.dart';

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

  final String _groupId = Config.liveStreamGroupId;
  Timer? _pollingTimer;
  Timer? _typingTimer;
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
  final int _connectionRetries = 0;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      _initializePlayer();
      await _initializeSocketConnection();
      await _loadInitialData();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to initialize live stream: $e';
        });
      }
    }
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
          _errorMessage = 'Failed to load video. Please check your connection.';
        });
      }
    }
  }

  Future<void> _initializeSocketConnection() async {
    if (!Config.enableLiveChat) {
      debugPrint('⚠️ Live chat disabled in configuration');
      return;
    }

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
    }
  }

  Future<void> _loadInitialData() async {
    try {
      // ✅ USE LIVE STREAM MESSAGES, NOT GROUP MESSAGES
      if (!_isConnected) {
        final messages = await _messageRepository.fetchLiveMessages();
        if (mounted) {
          setState(() {
            _messages.addAll(messages);
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
        if (user != null) {
          _socketService.sendMessage(int.tryParse(_groupId) ?? 1, {
            'groupId': _groupId,
            'content': content,
            'senderId': user.id,
          });
        }
      } else {
        // ✅ USE LIVE STREAM MESSAGE SENDING
        final sentMessage = await _messageRepository.sendLiveMessage(content);
        if (sentMessage != null && mounted) {
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
    _pollingTimer = Timer.periodic(
      Duration(seconds: Config.messagePollingInterval),
      (_) {
        if (mounted) _fetchNewMessages();
      },
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showFeatureDisabledMessage() {
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
      _isLoading = true;
    });
    await _initializeApp();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
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
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            color: _isConnected ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload video',
            onPressed: _loadVideo,
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

  Widget _buildMobileLayout(ThemeData theme, Size screenSize) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _isPlayerInitialized
              ? YoutubePlayer(controller: _controller)
              : Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  ),
                ),
        ),

        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Icon(
                _isConnected ? Icons.circle : Icons.circle_outlined,
                color: _isConnected ? Colors.green : Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isConnected ? 'LIVE NOW' : 'CONNECTING...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _isConnected ? Colors.red : Colors.grey,
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
        ),

        const Divider(height: 1),

        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  height: 48,
                  child: TabBar(
                    tabs: const [
                      Tab(text: 'Chat'),
                      Tab(text: 'Members'),
                    ],
                    indicatorColor: theme.colorScheme.primary,
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurface.withAlpha(
                      153,
                    ),
                  ),
                ),

                Expanded(
                  child: TabBarView(
                    children: [_buildChatTab(theme), _buildMembersTab(theme)],
                  ),
                ),
              ],
            ),
          ),
        ),
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
              Expanded(
                flex: 3,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _isPlayerInitialized
                      ? YoutubePlayer(controller: _controller)
                      : Container(
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.red,
                              ),
                            ),
                          ),
                        ),
                ),
              ),

              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.circle : Icons.circle_outlined,
                      color: _isConnected ? Colors.green : Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isConnected ? 'LIVE NOW' : 'CONNECTING...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _isConnected ? Colors.red : Colors.grey,
                        ),
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
              ),
            ],
          ),
        ),

        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.dividerColor)),
            ),
            child: _buildChatTab(theme),
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
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _isPlayerInitialized
                          ? YoutubePlayer(controller: _controller)
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.red,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),

              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.circle : Icons.circle_outlined,
                      color: _isConnected ? Colors.green : Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isConnected ? 'LIVE NOW' : 'CONNECTING...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _isConnected ? Colors.red : Colors.grey,
                        ),
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
              ),
            ],
          ),
        ),

        SizedBox(
          width: 400,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  height: 48,
                  child: TabBar(
                    tabs: const [
                      Tab(text: 'Chat'),
                      Tab(text: 'Members'),
                    ],
                    indicatorColor: theme.colorScheme.primary,
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurface.withAlpha(
                      153,
                    ),
                  ),
                ),

                Expanded(
                  child: TabBarView(
                    children: [_buildChatTab(theme), _buildMembersTab(theme)],
                  ),
                ),
              ],
            ),
          ),
        ),
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
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withAlpha(25),
            child: Icon(
              Icons.person,
              color: theme.colorScheme.primary,
              size: 20,
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
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withAlpha(25),
                  child: Icon(
                    Icons.person,
                    color: theme.colorScheme.primary,
                    size: 20,
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
