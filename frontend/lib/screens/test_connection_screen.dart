// screens/test_connection_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';

class TestConnectionScreen extends StatefulWidget {
  const TestConnectionScreen({super.key});

  @override
  State<TestConnectionScreen> createState() => _TestConnectionScreenState();
}

class _TestConnectionScreenState extends State<TestConnectionScreen> {
  String _response = 'Testing...';
  bool _isLoading = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _testBackendConnection();
  }

  Future<void> _testBackendConnection() async {
    setState(() {
      _isLoading = true;
      _response = 'Testing connection...';
    });
    try {
      final response = await ApiService.get('api/test');
      setState(() {
        _response = response.body;
        _isLoading = false;
        _isConnected = true;
      });
    } catch (e) {
      setState(() {
        _response = 'Error: ${e.toString()}';
        _isLoading = false;
        _isConnected = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Test'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isConnected ? Icons.check_circle : Icons.error,
                size: 80,
                color: _isConnected ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 24),
              Text(
                _isConnected ? 'Connected!' : 'Connection Failed',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      if (_isLoading) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        _response,
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _testBackendConnection,
                icon: const Icon(Icons.refresh),
                label: const Text('Test Again'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
