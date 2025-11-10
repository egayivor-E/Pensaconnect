import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../repositories/group_chat_repository.dart';
import '../models/group_message_model.dart';

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

    // Load initial messages
    await _loadInitialMessages();

    // Start real-time listening
    _setupRealtimeListener();

    // Setup typing detection
    _setupTypingDetection();
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
    final isMe = message.sender?['id'] == 1; // Replace with actual user ID
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primary.withOpacity(0.2),
              child: Text(
                _getInitials(message.sender?['full_name'] ?? 'U'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? colorScheme.primary : colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(
                      message.sender?['full_name'] ?? 'Unknown User',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  Text(
                    message.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isMe
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isMe
                          ? colorScheme.onPrimary.withOpacity(0.7)
                          : colorScheme.onSurface.withOpacity(0.5),
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
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
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
              color: Theme.of(context).colorScheme.surfaceVariant,
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
                fillColor: Theme.of(context).colorScheme.surfaceVariant,
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
      backgroundColor: Theme.of(context).colorScheme.background,
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
