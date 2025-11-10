// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final User? user; // 👈 optional for viewing another user

  const ProfileScreen({super.key, this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _repo = UserRepository();
  User? _user;
  bool _loading = true;
  bool _isOwnProfile = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // If user passed through navigation, show it directly
    if (widget.user != null) {
      setState(() {
        _user = widget.user;
        _isOwnProfile = false;
        _loading = false;
      });
    } else {
      await _loadCurrentUser();
    }
  }

  Future<void> _loadCurrentUser() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService().getToken();
      debugPrint("🪙 Loaded token: $token");

      if (token == null) {
        debugPrint("⚠️ No token found — user not logged in.");
        setState(() {
          _user = null;
          _loading = false;
        });
        return;
      }

      final user = await _repo.getCurrentUser(token);
      debugPrint(
        "📡 User fetch result: ${user != null ? '✅ Success' : '❌ Null user'}",
      );

      if (!mounted) return;

      setState(() {
        _user = user;
        _isOwnProfile = true;
        _loading = false;
      });
    } catch (e, stack) {
      debugPrint("❌ Error loading profile: $e");
      debugPrint("🧩 Stack trace: $stack");
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to load profile')));
    }
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Text('No profile available', style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isOwnProfile ? 'My Profile' : '${_user!.getFullName()}'),
        actions: _isOwnProfile
            ? [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))]
            : null,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          final card = _buildProfileCard(context, _user!, isWide);

          return RefreshIndicator(
            onRefresh: _isOwnProfile ? _loadCurrentUser : () async {},
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 48 : 16,
                vertical: 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: card,
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: _isOwnProfile
          ? FloatingActionButton.extended(
              onPressed: () async {
                final updated = await Navigator.of(context).push<User?>(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(user: _user!),
                  ),
                );
                if (updated != null && mounted) {
                  setState(() => _user = updated);
                }
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildProfileCard(BuildContext context, User user, bool isWide) {
    final theme = Theme.of(context);

    final avatar = CircleAvatar(
      radius: isWide ? 72 : 56,
      backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
      backgroundImage:
          (user.profilePicture != null && user.profilePicture!.isNotEmpty)
          ? NetworkImage(user.profilePicture!)
          : null,
      child: (user.profilePicture == null || user.profilePicture!.isEmpty)
          ? Icon(
              Icons.person,
              size: isWide ? 72 : 56,
              color: theme.colorScheme.primary,
            )
          : null,
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          user.getFullName(),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(user.email, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Text(
          user.createdAt != null
              ? 'Member since ${user.createdAt!.year}'
              : 'Member since -',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: user.roles.map((r) => Chip(label: Text(r))).toList(),
        ),
      ],
    );

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: isWide
            ? Row(
                children: [
                  avatar,
                  const SizedBox(width: 28),
                  Expanded(child: details),
                ],
              )
            : Column(children: [avatar, const SizedBox(height: 16), details]),
      ),
    );
  }
}
