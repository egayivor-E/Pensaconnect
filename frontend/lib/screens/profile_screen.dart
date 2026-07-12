// lib/screens/profile_screen.dart
import 'package:flutter/material.dart' hide Badge;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pensaconnect/config/config.dart';
import '../models/badge.dart';
import '../models/profile_view_model.dart';
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
    // Only meaningful for "my profile": ProfileViewModel.loadProfile()
    // always fetches the CURRENTLY AUTHENTICATED user's own stats via
    // authRepo.getCurrentUser() — it has no notion of "load stats for
    // this other user", so running it while viewing someone else's
    // profile would silently show the wrong person's numbers.
    if (widget.user == null) {
      context.read<ProfileViewModel>().loadProfile();
    }
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
      if (mounted) context.read<ProfileViewModel>().loadProfile();
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

  // ✅ FIX: /profile is now reached via context.go() from the drawer and
  // home avatar (see AppDrawer/home_screen fixes), which replaces the
  // whole navigation stack instead of pushing on top of it — so there's
  // often nothing left to pop, which is why no back arrow was showing and
  // the hardware/system back gesture had nowhere sensible to go. This
  // mirrors the same canPop-or-go-home fallback already used by
  // GroupChatsScreen.
  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
        ),
        body: Center(
          child: Text('No profile available', style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isOwnProfile ? 'My Profile' : '${_user!.getFullName()}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        card,
                        if (_isOwnProfile) ...[
                          const SizedBox(height: 20),
                          _buildStatsAndBadges(context),
                        ],
                      ],
                    ),
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
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, User user, bool isWide) {
    final theme = Theme.of(context);

    final avatar = CircleAvatar(
      radius: isWide ? 72 : 56,
      backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
      backgroundImage:
          (user.profilePicture != null && user.profilePicture!.isNotEmpty)
          ? NetworkImage(user.getProfilePictureUrl(Config.baseUrl)) // ← FIXED!
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

  // ✅ "Intelligent" profile section: real engagement stats (prayers,
  // testimonies, groups) and dynamically-computed achievement badges,
  // both sourced from the ProfileViewModel that already existed in this
  // codebase but was never actually wired into the UI. Fails quietly —
  // this is supplementary context, not core profile data, so a stats
  // fetch error shouldn't block or scare someone away from their own
  // profile page.
  Widget _buildStatsAndBadges(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<ProfileViewModel>(
      builder: (context, vm, _) {
        if (vm.isLoading && vm.badges.isEmpty) {
          return const _StatsAndBadgesSkeleton();
        }
        if (vm.error != null) {
          return const SizedBox.shrink();
        }

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your activity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: Icons.favorite_rounded,
                        color: const Color(0xFF14B8A6),
                        label: 'Prayers',
                        count: vm.prayersCount,
                      ),
                    ),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.auto_stories_rounded,
                        color: const Color(0xFFEC4899),
                        label: 'Testimonies',
                        count: vm.testimoniesCount,
                      ),
                    ),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.chat_bubble_rounded,
                        color: const Color(0xFF6366F1),
                        label: 'Groups',
                        count: vm.groupsCount,
                      ),
                    ),
                  ],
                ),
                if (vm.badges.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Badges',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: vm.badges
                        .map((badge) => _BadgeChip(badge: badge))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// A single stat (icon + count + label), used in the "Your activity" row.
// Deliberately plain (no gradient/shadow treatment) so the three of them
// read as data first — the badges below get the more decorative styling
// since those are meant to feel like little rewards.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          '$count',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}

// A single earned badge — same glossy gradient-circle treatment as the
// home screen's quick-action icons, so "achievement" reads as a
// consistent visual language across the app rather than a one-off style.
class _BadgeChip extends StatelessWidget {
  final Badge badge;

  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deepColor = Color.lerp(badge.color, Colors.black, 0.28)!;

    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [badge.color, deepColor],
              ),
              boxShadow: [
                BoxShadow(
                  color: badge.color.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(badge.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            badge.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// Lightweight loading placeholder shown while ProfileViewModel.loadProfile()
// is in flight — avoids the stats/badges card popping in abruptly once
// its network calls resolve.
class _StatsAndBadgesSkeleton extends StatelessWidget {
  const _StatsAndBadgesSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withOpacity(0.06);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: List.generate(3, (i) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 12),
                child: Column(
                  children: [
                    CircleAvatar(radius: 11, backgroundColor: base),
                    const SizedBox(height: 8),
                    Container(
                      width: 28,
                      height: 14,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
