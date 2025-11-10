import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/member.dart';
import '../models/message_model.dart'; // ✅ correct import
import '../repositories/message_repository.dart';
import '../repositories/auth_repository.dart';

class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({super.key});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  late YoutubePlayerController _controller;
  final List<Member> _members = List.generate(
    10,
    (i) => Member(id: 'm$i', name: 'Member ${i + 1}', isOnline: true),
  );
  final List<Message> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  final MessageRepository _repository = MessageRepository();
  final AuthRepository _authRepository = AuthRepository();
  final String _groupId = 'live';
  Timer? _pollingTimer;
  String? _authToken;
  bool _isPlayerInitialized = false;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _loadAuthToken();
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
      await _controller.loadVideoById(videoId: 'YOUR_YOUTUBE_VIDEO_ID');
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

  Future<void> _loadAuthToken() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoading = true;
      });

      // ✅ fixed: call new method
      _authToken = await _authRepository.getAccessToken();

      if (_authToken == null || _authToken!.isEmpty) {
        debugPrint("❌ No auth token available. User may need to log in.");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Please log in to access the live stream';
          });
        }
        return;
      }

      await _fetchNewMessages();

      _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) {
          _fetchNewMessages();
        }
      });

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading auth token: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Authentication error: $e';
        });
      }
    }
  }

  Future<void> _fetchNewMessages() async {
    if (_authToken == null || !mounted) return;

    try {
      final messages = await _repository.fetchGroupMessages(_groupId);

      if (!mounted) return;

      setState(() {
        for (var msg in messages) {
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
          }
        }
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error fetching messages: $e');
    }
  }

  void _sendMessage() async {
    if (_authToken == null || _messageController.text.isEmpty || !mounted) {
      return;
    }

    try {
      final content = _messageController.text.trim();
      final sentMessage = await _repository.sendGroupMessage(_groupId, content);

      if (sentMessage != null && mounted) {
        setState(() {
          _messages.add(sentMessage);
        });
        _messageController.clear();
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
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

  Future<void> _retryAuthentication() async {
    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });
    await _loadAuthToken();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _controller.close();
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

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
                  onPressed: _retryAuthentication,
                  child: const Text('Retry'),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload video',
            onPressed: () {
              _loadVideo();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Reauthenticate',
            onPressed: _retryAuthentication,
          ),
        ],
      ),
      body: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = width * 9 / 16;
              return SizedBox(
                width: width,
                height: height,
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
              );
            },
          ),

          // Live Info
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.circle, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'LIVE NOW',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    '${_members.length * 20} watching',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                    overflow: TextOverflow.ellipsis,
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
                    constraints: const BoxConstraints(maxHeight: 48),
                    child: TabBar(
                      tabs: const [
                        Tab(text: 'Chat'),
                        Tab(text: 'Members'),
                      ],
                      indicatorColor: theme.colorScheme.primary,
                      labelColor: theme.colorScheme.primary,
                      unselectedLabelColor: theme.colorScheme.onSurface
                          .withOpacity(0.6),
                      isScrollable: isSmallScreen,
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      children: [
                        // Chat Tab
                        Column(
                          children: [
                            Expanded(
                              child: _messages.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No messages yet. Be the first to chat!',
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _chatScrollController,
                                      padding: const EdgeInsets.all(8),
                                      itemCount: _messages.length,
                                      itemBuilder: (context, index) {
                                        final msg = _messages[index];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                backgroundColor: theme
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.1),
                                                child: Icon(
                                                  Icons.person,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      msg.senderId,
                                                      style: theme
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                    ),
                                                    Text(
                                                      msg.content,
                                                      style: theme
                                                          .textTheme
                                                          .bodyMedium,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _messageController,
                                        decoration: InputDecoration(
                                          hintText: 'Type your message...',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 12,
                                              ),
                                        ),
                                        onSubmitted: (_) => _sendMessage(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    CircleAvatar(
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.send,
                                          color: Colors.white,
                                        ),
                                        onPressed: _sendMessage,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Members Tab
                        ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _members.length,
                          itemBuilder: (context, index) {
                            final member = _members[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.primary
                                    .withOpacity(0.1),
                                child: Icon(
                                  Icons.person,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              title: Text(
                                member.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                member.isOnline ? 'Online' : 'Offline',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.chat),
                                onPressed: () {},
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
