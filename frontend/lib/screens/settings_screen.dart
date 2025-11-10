import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';
import '../repositories/auth_repository.dart';
import '../repositories/notification_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthRepository _authRepository = AuthRepository();
  late NotificationRepository _notificationRepository;
  bool _notificationsEnabled = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _notificationRepository = NotificationRepository();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      });
    } catch (e) {
      _showError('Failed to load settings');
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _saveNotificationPreference(bool enabled) async {
    try {
      setState(() {
        _notificationsEnabled = enabled;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', enabled);

      // Update backend if authenticated
      final token = prefs.getString('auth_token');
      if (token != null) {
        await _notificationRepository.updateNotificationPreference(
          token,
          enabled,
        );
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _notificationsEnabled = !enabled;
      });
      _showError('Failed to update notification settings');
      debugPrint('Error saving notification preference: $e');
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    bool? confirm = await _showLogoutConfirmation();
    if (confirm != true) return;

    setState(() {
      _isLoggingOut = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // Call backend logout
      await _authRepository.logout();

      // Clear local storage
      await Future.wait([
        prefs.remove('auth_token'),
        prefs.remove('user_data'),
        prefs.remove('notifications_enabled'),
      ]);

      // Navigate to login screen
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      _showError('Logout failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  Future<bool?> _showLogoutConfirmation() {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        surfaceTintColor: theme.cardColor,
        title: Text('Logout', style: theme.textTheme.titleMedium),
        content: Text(
          'Are you sure you want to logout?',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _errorMessage = message;
    });

    // Auto-hide error after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _errorMessage == message) {
        setState(() {
          _errorMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    // Platform detection
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    final isTablet =
        MediaQuery.of(context).size.width >= 600 &&
        MediaQuery.of(context).size.width < 1200;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: !isDesktop,
        elevation: 0,
        backgroundColor: theme.appBarTheme.backgroundColor,
        actions: [
          if (_isLoggingOut)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _buildContent(theme, isDarkMode, isMobile, isTablet, isDesktop),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    bool isDarkMode,
    bool isMobile,
    bool isTablet,
    bool isDesktop,
  ) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 800),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile
            ? 16
            : isTablet
            ? 24
            : 32,
        vertical: 16,
      ),
      child: Column(
        children: [
          if (_errorMessage != null) _buildErrorBanner(theme),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Preferences Section
                  _buildSectionTitle(theme, 'Preferences'),
                  const SizedBox(height: 12),
                  _buildPreferencesCard(theme, isDarkMode),

                  const SizedBox(height: 24),

                  // Account Section
                  _buildSectionTitle(theme, 'Account'),
                  const SizedBox(height: 12),
                  _buildAccountCard(theme),

                  const SizedBox(height: 24),

                  // Support Section
                  _buildSectionTitle(theme, 'Support'),
                  const SizedBox(height: 12),
                  _buildSupportCard(theme),

                  const SizedBox(height: 32),

                  // Logout Button
                  _buildLogoutButton(theme),

                  // Bottom padding for better scrolling
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.onErrorContainer,
            ),
            onPressed: () => setState(() => _errorMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary.withOpacity(0.7),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildPreferencesCard(ThemeData theme, bool isDarkMode) {
    return Card(
      elevation: 1,
      color: theme.cardColor,
      surfaceTintColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _buildSwitchTile(
            theme: theme,
            icon: Icons.dark_mode_outlined,
            title: 'Dark Mode',
            value: isDarkMode,
            onChanged: (value) {
              final themeProvider = context.read<ThemeProvider>();
              // ✅ FIXED: Use the correct method name from your ThemeProvider
              themeProvider.toggleDarkMode(value);
            },
          ),
          Divider(height: 1, indent: 16, color: theme.dividerColor),
          _buildSwitchTile(
            theme: theme,
            icon: Icons.notifications_active_outlined,
            title: 'Enable Notifications',
            value: _notificationsEnabled,
            onChanged: _saveNotificationPreference,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(ThemeData theme) {
    return Card(
      elevation: 1,
      color: theme.cardColor,
      surfaceTintColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _buildNavigationTile(
            theme: theme,
            icon: Icons.person_outline,
            title: 'Profile',
            route: '/profile',
          ),
          Divider(height: 1, indent: 16, color: theme.dividerColor),
          _buildNavigationTile(
            theme: theme,
            icon: Icons.lock_outline,
            title: 'Change Password',
            route: '/change-password',
          ),
        ],
      ),
    );
  }

  Widget _buildSupportCard(ThemeData theme) {
    return Card(
      elevation: 1,
      color: theme.cardColor,
      surfaceTintColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _buildNavigationTile(
            theme: theme,
            icon: Icons.help_outline,
            title: 'Help & Support',
            route: '/help-support',
          ),
          Divider(height: 1, indent: 16, color: theme.dividerColor),
          _buildNavigationTile(
            theme: theme,
            icon: Icons.description_outlined,
            title: 'Terms & Privacy',
            route: '/terms-privacy',
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, size: 22, color: theme.colorScheme.onSurface),
      title: Text(title, style: theme.textTheme.bodyLarge),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: theme.colorScheme.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minLeadingWidth: 24,
    );
  }

  Widget _buildNavigationTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String route,
  }) {
    return ListTile(
      leading: Icon(icon, size: 22, color: theme.colorScheme.onSurface),
      title: Text(title, style: theme.textTheme.bodyLarge),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: theme.colorScheme.onSurface.withOpacity(0.6),
      ),
      onTap: () => context.push(route),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      minLeadingWidth: 24,
    );
  }

  Widget _buildLogoutButton(ThemeData theme) {
    return Center(
      child: SizedBox(
        width: 200,
        child: FilledButton.icon(
          onPressed: _isLoggingOut ? null : _logout,
          icon: _isLoggingOut
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onError,
                  ),
                )
              : Icon(Icons.logout, size: 18),
          label: Text(_isLoggingOut ? 'Logging out...' : 'Logout'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
