// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Add this import
import 'package:pensaconnect/config/config.dart';

class AnonymousChatScreen extends StatefulWidget {
  final String chatId;
  final String topic;

  const AnonymousChatScreen({
    super.key,
    required this.chatId,
    required this.topic,
  });

  @override
  State<AnonymousChatScreen> createState() => _AnonymousChatScreenState();
}

class _AnonymousChatScreenState extends State<AnonymousChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isSending = false;
  bool _envLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeEnv();
  }

  Future<void> _initializeEnv() async {
    await dotenv.load(); // Load environment variables
    setState(() {
      _envLoaded = true;
    });
  }

  Future<void> _sendMessage() async {
    if (!_envLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('App not ready yet. Please wait...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      // Use your Config class
      final apiUrl = Config.anonymousMessagesUrl;
      print('Sending to: $apiUrl'); // For debugging

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'topic': widget.topic,
          'chat_id': widget.chatId,
          'message': text,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        setState(() {
          _messages.add({
            "sender": "You",
            "text": text,
            "status": "sent",
            "timestamp": DateTime.now().toString(),
          });
        });

        _messageController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message sent to admin!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to send message');
      }
    } catch (e) {
      print('Error sending message: $e');

      // Fallback: save message locally if server fails
      setState(() {
        _messages.add({
          "sender": "You",
          "text": text,
          "status": "failed",
          "timestamp": DateTime.now().toString(),
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_envLoaded) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading app configuration...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic),
        backgroundColor: Colors.blueGrey,
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.blueGrey[50],
            child: const Text(
              'Messages are sent anonymously to admin',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          "No messages yet",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        Text(
                          "Start a conversation with admin",
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isFailed = message['status'] == 'failed';

                      return Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isFailed
                                ? Colors.orange[50]
                                : Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFailed
                                  ? Colors.orange[100]!
                                  : Colors.blue[100]!,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['sender']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isFailed
                                      ? Colors.orange[700]
                                      : Colors.blue[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message['text']!,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    isFailed
                                        ? Icons.error_outline
                                        : Icons.check_circle,
                                    size: 12,
                                    color: isFailed
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isFailed
                                        ? "Failed to send"
                                        : "Sent to admin",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isFailed
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Type your message to admin...",
                      border: const OutlineInputBorder(),
                      suffixIcon: _isSending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    enabled: !_isSending && _envLoaded,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: (_isSending || !_envLoaded)
                        ? Colors.grey
                        : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    onPressed: (_isSending || !_envLoaded)
                        ? null
                        : _sendMessage,
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
