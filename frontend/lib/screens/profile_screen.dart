// screens/profile_screen.dart
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfilePost {
  final String imageUrl;
  final bool isVideo;
  final int likes;
  const _ProfilePost(this.imageUrl, {this.isVideo = false, this.likes = 0});
}

class _Badge {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge(this.icon, this.label, this.color);
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _avatarFile;
  File? _coverFile;
  bool _uploadingAvatar = false;

  String _name = 'Sarah Johnson';
  String _bio = 'Growing in faith, one day at a time 🙏✨';
  String _role = 'Youth Leader';
  final DateTime _memberSince = DateTime(2023, 3, 1);

  final Map<String, int> _stats = const {
    'Prayers': 24,
    'Testimonies': 15,
    'Groups': 3,
  };

  final List<_Badge> _badges = const [
    _Badge(Icons.emoji_events, 'Faithful', Colors.amber),
    _Badge(Icons.forum, 'Encourager', Colors.blue),
    _Badge(Icons.favorite, 'Prayer Warrior', Colors.red),
    _Badge(Icons.star, 'New Believer', Colors.green),
    _Badge(Icons.groups, 'Community Builder', Colors.purple),
    _Badge(Icons.menu_book, 'Word Digger', Colors.teal),
  ];

  final List<_ProfilePost> _posts = const [
    _ProfilePost('https://picsum.photos/seed/pensa1/600/600'),
    _ProfilePost('https://picsum.photos/seed/pensa2/600/600', isVideo: true),
    _ProfilePost('https://picsum.photos/seed/pensa3/600/600'),
    _ProfilePost('https://picsum.photos/seed/pensa4/600/600'),
    _ProfilePost('https://picsum.photos/seed/pensa5/600/600'),
    _ProfilePost('https://picsum.photos/seed/pensa6/600/600', isVideo: true),
    _ProfilePost('https://picsum.photos/seed/pensa7/600/600'),
    _ProfilePost('https://picsum.photos/seed/pensa8/600/600'),
    _ProfilePost('https://picsum.photos/seed/pensa9/600/600'),
  ];

  Future<void> _pickAvatar() async {
    final source = await _showImageSourceSheet(
      title: 'Update profile photo',
      allowRemove: _avatarFile != null,
    );
    if (source == null) return;
    if (source == _PickAction.remove) {
      setState(() => _avatarFile = null);
      return;
    }
    final picked = await _picker.pickImage(
      source: source == _PickAction.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked == null) return;
    setState(() => _uploadingAvatar = true);
    // TODO: wire to UserRepository.updateUserProfile / upload endpoint once
    // the backend media-upload route is available. For now we show an
    // optimistic local preview so the UX is fully usable.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() {
      _avatarFile = File(picked.path);
      _uploadingAvatar = false;
    });
    _showSnack('Profile photo updated');
  }

  Future<void> _pickCover() async {
    final source = await _showImageSourceSheet(
      title: 'Update cover photo',
      allowRemove: _coverFile != null,
    );
    if (source == null) return;
    if (source == _PickAction.remove) {
      setState(() => _coverFile = null);
      return;
    }
    final picked = await _picker.pickImage(
      source: source == _PickAction.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() => _coverFile = File(picked.path));
    _showSnack('Cover photo updated');
  }

  Future<_PickAction?> _showImageSourceSheet({
    required String title,
    required bool allowRemove,
  }) {
    return showModalBottomSheet<_PickAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, _PickAction.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, _PickAction.gallery),
              ),
              if (allowRemove)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Remove current photo',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => Navigator.pop(ctx, _PickAction.remove),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _editProfileSheet() async {
    final nameController = TextEditingController(text: _name);
    final bioController = TextEditingController(text: _bio);
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Text(
                'Edit Profile',
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: bioController,
                maxLines: 3,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  prefixIcon: Icon(Icons.edit_note),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, {
                    'name': nameController.text.trim(),
                    'bio': bioController.text.trim(),
                  }),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Save changes'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (result != null) {
      setState(() {
        if (result['name']!.isNotEmpty) _name = result['name']!;
        _bio = result['bio'] ?? _bio;
      });
      _showSnack('Profile updated');
    }
  }

  void _openPost(_ProfilePost post) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _PostViewer(post: post),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text(
          'Are you sure you want to log out of PensaConnect?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // TODO: hook into the real AuthProvider/AuthNotifier logout() once the
      // app's auth wiring is consolidated.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              stretch: true,
              expandedHeight: 300,
              backgroundColor: primary,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                  ),
                  tooltip: 'Settings',
                  onPressed: () =>
                      DefaultTabController.of(context).animateTo(2),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [StretchMode.zoomBackground],
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cover photo / gradient banner
                    GestureDetector(
                      onTap: _pickCover,
                      child: _coverFile != null
                          ? Image.file(_coverFile!, fit: BoxFit.cover)
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    primary,
                                    theme.colorScheme.secondary,
                                  ],
                                ),
                              ),
                            ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.05),
                            Colors.black.withOpacity(0.55),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 96,
                      child: _RoundIconButton(
                        icon: Icons.camera_alt_outlined,
                        onTap: _pickCover,
                        tooltip: 'Change cover photo',
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: _uploadingAvatar
                                      ? Container(
                                          color: theme
                                              .colorScheme
                                              .primaryContainer,
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                            ),
                                          ),
                                        )
                                      : (_avatarFile != null
                                            ? Image.file(
                                                _avatarFile!,
                                                fit: BoxFit.cover,
                                              )
                                            : Image.asset(
                                                'assets/images/user.png',
                                                fit: BoxFit.cover,
                                              )),
                                ),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: _RoundIconButton(
                                  icon: Icons.edit,
                                  size: 32,
                                  iconSize: 16,
                                  onTap: _pickAvatar,
                                  tooltip: 'Change profile photo',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              _role,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -18),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _stats.entries.map((e) {
                            final isLast = e.key == _stats.keys.last;
                            return Row(
                              children: [
                                Column(
                                  children: [
                                    Text(
                                      '${e.value}',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: primary,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      e.key,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                if (!isLast)
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    width: 1,
                                    height: 30,
                                    color: theme.dividerColor,
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _bio,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Member since ${DateFormat('MMMM yyyy').format(_memberSince)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _editProfileSheet,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit Profile'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyTabBarDelegate(
                TabBar(
                  labelColor: primary,
                  unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(
                    0.5,
                  ),
                  indicatorColor: primary,
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(icon: Icon(Icons.grid_on_rounded), text: 'Posts'),
                    Tab(
                      icon: Icon(Icons.emoji_events_outlined),
                      text: 'Badges',
                    ),
                    Tab(icon: Icon(Icons.settings_outlined), text: 'Settings'),
                  ],
                ),
                theme.scaffoldBackgroundColor,
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _buildPostsGrid(theme),
              _buildBadgesGrid(theme),
              _buildSettings(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostsGrid(ThemeData theme) {
    if (_posts.isEmpty) {
      return _EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No posts yet',
        subtitle:
            'Share a testimony or prayer with a photo and it will show up here.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      itemCount: _posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, i) {
        final post = _posts[i];
        return GestureDetector(
          onTap: () => _openPost(post),
          child: Hero(
            tag: 'post_${post.imageUrl}',
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  post.imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(color: theme.colorScheme.surfaceVariant);
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceVariant,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
                if (post.isVideo)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 20,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadgesGrid(ThemeData theme) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _badges.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.6,
      ),
      itemBuilder: (context, i) {
        final b = _badges[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: b.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: b.color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: b.color.withOpacity(0.18),
                child: Icon(b.icon, color: b.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  b.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettings(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsGroup(
          title: 'Account',
          children: [
            _SettingsTile(
              icon: Icons.email_outlined,
              title: 'Email',
              subtitle: 'user@example.com',
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.lock_outline,
              title: 'Password',
              subtitle: '••••••••',
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy',
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsGroup(
          title: 'Support',
          children: [
            _SettingsTile(
              icon: Icons.help_outline,
              title: 'Help Center',
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About PensaConnect',
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Log Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

enum _PickAction { camera, gallery, remove }

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final button = Material(
      color: primary,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: List.generate(children.length * 2 - 1, (i) {
              if (i.isEven) return children[i ~/ 2];
              return const Divider(height: 1, indent: 56);
            }),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: primary.withOpacity(0.1),
        child: Icon(icon, color: primary, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: theme.colorScheme.onSurface.withOpacity(0.25),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;
  _StickyTabBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _PostViewer extends StatelessWidget {
  final _ProfilePost post;
  const _PostViewer({required this.post});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        extendBodyBehindAppBar: true,
        body: Center(
          child: Hero(
            tag: 'post_${post.imageUrl}',
            child: InteractiveViewer(
              child: Image.network(post.imageUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
