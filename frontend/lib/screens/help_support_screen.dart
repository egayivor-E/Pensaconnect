import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpAndSupportScreen extends StatelessWidget {
  const HelpAndSupportScreen({super.key});

  Future<void> _launchEmail() async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: 'support@pensaconnect.com',
      query: 'subject=Support Request&body=Please describe your issue here...',
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  Future<void> _launchWebsite() async {
    final url = Uri.parse('https://pensaconnect.com/help');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'We’re here to help',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you’re experiencing any issues or have questions about PensaConnect, '
                    'feel free to reach out using any of the options below.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    color: theme.cardColor,
                    surfaceTintColor: theme.cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.email_outlined),
                          title: const Text('Email Us'),
                          subtitle: const Text('support@pensaconnect.com'),
                          onTap: _launchEmail,
                        ),
                        Divider(
                          height: 1,
                          color: theme.dividerColor,
                          indent: 16,
                        ),
                        ListTile(
                          leading: const Icon(Icons.language_outlined),
                          title: const Text('Visit Help Center'),
                          subtitle: const Text('pensaconnect.com/help'),
                          onTap: _launchWebsite,
                        ),
                        Divider(
                          height: 1,
                          color: theme.dividerColor,
                          indent: 16,
                        ),
                        const ListTile(
                          leading: Icon(Icons.phone_outlined),
                          title: Text('Call Us'),
                          subtitle: Text('+233 55 123 4567'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Text(
                      'Our support team typically replies within 24 hours.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
