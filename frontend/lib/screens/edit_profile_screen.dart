// lib/screens/edit_profile_screen.dart
// ignore_for_file: unnecessary_null_comparison, unused_element

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for Uint8List
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart'
    as http; // used to build MultipartFile passed to ApiService
import '../models/user.dart';
import '../repositories/user_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  final User user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = UserRepository();
  final _picker = ImagePicker();

  late TextEditingController _usernameCtrl;
  late TextEditingController _emailCtrl;

  // 🗑️ REMOVED: File? _pickedImageFile;
  // 🗑️ REMOVED: XFile? _pickedXFile;

  // ✅ NEW: Store picked image data in bytes for preview (Web/Native)
  Uint8List? _pickedImageBytes;
  // ✅ NEW: Keep XFile only for the actual upload logic (provides path/name)
  XFile? _pickedXFileForUpload;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.user.username);
    _emailCtrl = TextEditingController(text: widget.user.email);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // 🖼️ NEW HELPER FUNCTION TO FIX THE URL ISSUE
  // Simple usage with the repository helper
  // This is used for the NetworkImage when no new image is picked.
  String? _getProfilePictureUrl() {
    return UserRepository.getProfilePictureUrl(widget.user.profilePicture);
  }

  Future<void> _pickImage() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (xfile == null) return;

      // Read the bytes asynchronously right after picking (safe for all platforms)
      final bytes = await xfile.readAsBytes();

      if (!mounted) return;
      setState(() {
        _pickedImageBytes = bytes;
        _pickedXFileForUpload =
            xfile; // Store XFile for path/name access during upload
      });
    } catch (e) {
      debugPrint('Image pick error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to pick image')));
    }
  }

  Future<void> _saveAll() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      // 1) Update text fields (username/email) via repository
      final updates = {
        'username': _usernameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
      };
      final updated = await _repo.updateUserProfile(widget.user.id, updates);

      // 2) If an image was picked (we have bytes), upload it
      if (_pickedImageBytes != null && _pickedXFileForUpload != null) {
        // ✅ Simplified upload logic: always use bytes now
        http.MultipartFile mfile = http.MultipartFile.fromBytes(
          'avatar',
          _pickedImageBytes!,
          filename:
              _pickedXFileForUpload!.name, // Use the stored XFile for filename
        );

        // Use ApiService.postMultipart('users/me/avatar')
        final resp = await ApiService.postMultipart(
          'users/me/avatar',
          files: [mfile],
        );

        debugPrint('Avatar upload status: ${resp.statusCode}');
      }

      // 3) Re-fetch the current user to get updated profilePicture/fields
      final token = await AuthService().getToken();
      final refreshed = token == null
          ? null
          : await _repo.getCurrentUser(token);

      if (!mounted) return;

      setState(() => _saving = false);

      if (refreshed != null) {
        // return updated user to caller
        Navigator.of(context).pop(refreshed);
      } else if (updated != null) {
        Navigator.of(context).pop(updated);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No updates applied')));
      }
    } catch (e, st) {
      debugPrint('Save error: $e\n$st');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save profile')));
    }
  }

  Widget _buildAvatarPreview(double radius) {
    ImageProvider? provider;

    // 1. New Image Picked (Use stored bytes for preview on all platforms)
    if (_pickedImageBytes != null) {
      provider = MemoryImage(_pickedImageBytes!);
    }
    // 2. Existing Profile Picture (NetworkImage)
    else {
      // ✅ FIX: Use the repository helper to get the full absolute URL
      final profileUrl = UserRepository.getProfilePictureUrl(
        widget.user.profilePicture,
      );

      if (profileUrl != null && profileUrl.isNotEmpty) {
        provider = NetworkImage(profileUrl);
      }
    }

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        CircleAvatar(
          radius: radius,
          // Fallback to a plain color/icon if provider is null
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          backgroundImage: provider,
          child: provider == null ? const Icon(Icons.person, size: 36) : null,
        ),
        Positioned(
          bottom: 4,
          right: 4,
          child: InkWell(
            onTap: _pickImage,
            customBorder: const CircleBorder(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          final padding = EdgeInsets.symmetric(
            horizontal: isWide ? 64 : 16,
            vertical: 24,
          );

          return SingleChildScrollView(
            padding: padding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header area with avatar + quick info
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAvatarPreview(isWide ? 72 : 56),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.user.username,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.user.email,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Form
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _usernameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Username required'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _emailCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Email required'
                                    : null,
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _saving ? null : _saveAll,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save),
                                  label: Text(
                                    _saving ? 'Saving...' : 'Save Changes',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
