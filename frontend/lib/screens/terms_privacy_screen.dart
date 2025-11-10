import 'package:flutter/material.dart';

class TermsAndPrivacyScreen extends StatelessWidget {
  const TermsAndPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Privacy')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Card(
                color: theme.cardColor,
                surfaceTintColor: theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Terms of Service',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'By using PensaConnect, you agree to comply with our terms of service. '
                        'You are responsible for keeping your account credentials secure '
                        'and using our services lawfully.',
                      ),
                      const SizedBox(height: 24),
                      Text('Privacy Policy', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        'We value your privacy and use your data only to improve your experience. '
                        'We never sell or share personal information without consent, '
                        'except as required by law.',
                      ),
                      const SizedBox(height: 24),
                      Text('Data Usage', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        'We collect minimal analytics data to enhance app performance. '
                        'You can request data deletion at any time by contacting our team.',
                      ),
                      const SizedBox(height: 24),
                      Text('Contact Us', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        'For any legal or privacy questions, email us at privacy@pensaconnect.com.',
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: Text(
                          '© 2025 PensaConnect. All rights reserved.',
                          style: theme.textTheme.bodySmall,
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
    );
  }
}
