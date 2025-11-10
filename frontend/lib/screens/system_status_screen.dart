import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class SystemStatusScreen extends StatefulWidget {
  const SystemStatusScreen({super.key});
  @override
  State<SystemStatusScreen> createState() => _SystemStatusScreenState();
}

class _SystemStatusScreenState extends State<SystemStatusScreen> {
  String status = 'Checking...';
  String raw = '';

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    final url = Uri.parse('${AppConfig.backendUrl}/api/v1/health');
    try {
      final res = await http.get(url);
      setState(() {
        status = res.statusCode == 200 ? 'OK' : 'Degraded';
        raw = res.body;
      });
    } catch (e) {
      setState(() {
        status = 'Down';
        raw = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Status')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('API Status: $status', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            const Text('Response:'),
            const SizedBox(height: 8),
            SelectableText(raw),
            const Spacer(),
            ElevatedButton(onPressed: _checkHealth, child: const Text('Recheck'))
          ],
        ),
      ),
    );
  }
}
