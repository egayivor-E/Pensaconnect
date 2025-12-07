import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pensaconnect/providers/auth_provider.dart';
import 'package:provider/provider.dart';

import '../repositories/group_chat_repository.dart';
import '../models/group_message_model.dart';
import '../services/socketio_service.dart';

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
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<GroupMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _isConnected = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  StreamSubscription<List<GroupMessage>>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _groupRepo = context.read<GroupChatRepository>();

    // ✅ Initialize Socket.IO service FIRST
    try {
      await SocketIoService().initialize();
      debugPrint('✅ SocketIoService initialized');
    } catch (e) {
      debugPrint('❌ SocketIoService init error: $e');
    }

    // Load initial messages
    await _loadInitialMessages();

    // Start real-time listening
    _setupRealtimeListener();

    // ✅ Join WebSocket room with delay
    await Future.delayed(const Duration(milliseconds: 500));
    _joinSocketRoom();

    // Setup typing detection
    _setupTypingDetection();
  }

  void _joinSocketRoom() {
    try {
      debugPrint('🚀 Joining WebSocket room for group ${widget.groupId}');

      // Call watchMessages which will trigger connection
      _groupRepo.watchMessages(widget.groupId);

      // Manually emit join_group if needed
      final socketService = SocketIoService();
      socketService.debugConnectionStatus(widget.groupId);
    } catch (e) {
      debugPrint('⚠️ Error joining socket room: $e');
    }
  }

  Future<void> _loadInitialMessages() async {
    try {
      final messages = await _groupRepo.getMessages(widget.groupId);
      if (mounted) {
        setState(() {
          _messages = messages;
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _loading = false;
        });
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

  void _setupRealtimeListener() {
    _messageSubscription = _groupRepo
        .watchMessages(widget.groupId)
        .listen(
          (newMessages) {
            if (mounted) {
              setState(() {
                for (final msg in newMessages) {
                  if (!_messages.any((m) => m.id == msg.id)) {
                    _messages.add(msg);
                  }
                }

                _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                _isConnected = true;
              });
              _scrollToBottom();
            }
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
      // Send typing start event
      // _groupRepo.sendTypingStart(widget.groupId);

      _typingTimer = Timer(const Duration(seconds: 2), () {
        // Send typing stop event
        // _groupRepo.sendTypingStop(widget.groupId);
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

    setState(() => _sending = true);

    try {
      // Clear typing state
      _typingTimer?.cancel();
      // _groupRepo.sendTypingStop(widget.groupId);

      // Send via WebSocket for real-time delivery
      await _groupRepo.sendMessage(groupId: widget.groupId, content: text);

      _controller.clear();
      _focusNode.unfocus();
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageBubble(GroupMessage message) {
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    final isMe = message.sender?['id'] == currentUserId;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get profile picture URL
    final profilePictureUrl = _getProfilePictureUrl(message.sender);
    final fullName = message.sender?['full_name'] ?? 'Unknown User';

    // Calculate if message is short for better sizing
    final messageLength = message.content.length;
    final isShortMessage = messageLength < 25;
    final isVeryShort = messageLength < 10;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _buildModernProfileAvatar(profilePictureUrl, fullName),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      fullName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withOpacity(0.6),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: isVeryShort
                        ? double
                              .infinity // Unlimited width (will shrink to content)
                        : MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: isShortMessage ? 14 : 16,
                    vertical: isShortMessage ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isMe
                          ? const Radius.circular(18)
                          : const Radius.circular(4),
                      bottomRight: isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isMe ? 0.1 : 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                        spreadRadius: 0.5,
                      ),
                    ],
                    gradient: isMe
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colorScheme.primary,
                              colorScheme.primary.withOpacity(0.95),
                            ],
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isMe ? Colors.white : colorScheme.onSurface,
                          height: 1.4,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatModernTime(message.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: isMe
                                  ? Colors.white.withOpacity(0.8)
                                  : colorScheme.onSurface.withOpacity(0.4),
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
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
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildModernProfileAvatar(profilePictureUrl, fullName),
          ],
        ],
      ),
    );
  }

  Widget _buildModernProfileAvatar(String? profilePictureUrl, String fullName) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: profilePictureUrl != null && profilePictureUrl.isNotEmpty
            ? Image.network(
                profilePictureUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _buildFallbackAvatar(colorScheme, fullName);
                },
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallbackAvatar(colorScheme, fullName);
                },
              )
            : _buildFallbackAvatar(colorScheme, fullName),
      ),
    );
  }

  Widget _buildFallbackAvatar(ColorScheme colorScheme, String fullName) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _getInitials(fullName),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageStatus(GroupMessage message) {
    final colorScheme = Theme.of(context).colorScheme;

    if (message.readBy.length > 1) {
      // Message read by multiple people
      return Icon(
        Icons.done_all_rounded,
        size: 14,
        color: Colors.white.withOpacity(0.9),
      );
    } else if (message.readBy.isNotEmpty) {
      // Message delivered and read
      return Icon(
        Icons.done_all_rounded,
        size: 14,
        color: colorScheme.secondary.withOpacity(0.9),
      );
    } else {
      // Message sent (not read yet)
      return Icon(
        Icons.done_rounded,
        size: 14,
        color: Colors.white.withOpacity(0.7),
      );
    }
  }

  String _formatModernTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (messageDate == today) {
      return DateFormat('h:mm a').format(dateTime).toLowerCase();
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(dateTime).inDays < 7) {
      return DateFormat('EEE').format(dateTime);
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }

  // Don't forget to import this at the top of your file:
  // import 'package:intl/intl.dart';

  String? _getProfilePictureUrl(Map<String, dynamic>? sender) {
    if (sender == null) return null;

    // Check multiple possible field names
    final profilePicture =
        sender['profile_picture'] ??
        sender['profilePicture'] ??
        sender['avatar'] ??
        sender['profile_image'] ??
        sender['senderProfilePicture'];

    if (profilePicture == null || profilePicture.toString().isEmpty) {
      return null;
    }

    final String profilePictureStr = profilePicture.toString();

    // Check if it's already a full URL
    if (profilePictureStr.startsWith('http://') ||
        profilePictureStr.startsWith('https://')) {
      return profilePictureStr;
    }

    // If it's a relative path, prepend your base URL
    final baseUrl =
        'http://127.0.0.1:5000'; // Replace with your actual server URL

    // Remove leading slash if present to avoid double slashes
    final cleanPath = profilePictureStr.startsWith('/')
        ? profilePictureStr.substring(1)
        : profilePictureStr;

    return '$baseUrl/$cleanPath';
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isConnected
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isConnected ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isConnected ? Icons.circle : Icons.circle_outlined,
            size: 8,
            color: _isConnected ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            _isConnected ? 'Connected' : 'Connecting...',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    if (!_isTyping) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            child: Text(
              '?',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Typing...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _controller.clear();
                          _focusNode.unfocus();
                        },
                      )
                    : null,
              ),
              maxLines: null,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                )
              : IconButton.filled(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: const Size(48, 48),
                  ),
                ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _typingTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.groupName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              '${_messages.length} messages',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
        actions: [
          _buildConnectionStatus(),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialMessages,
            tooltip: 'Refresh messages',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                        Text(
                          'Start the conversation!',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + 1, // +1 for typing indicator
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return _buildTypingIndicator();
                      }
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }
}
