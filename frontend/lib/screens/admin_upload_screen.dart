import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/worship_song.dart';
import '../services/song_service.dart';
import '../providers/auth_provider.dart'; // Your auth provider

class AdminUploadScreen extends StatefulWidget {
  const AdminUploadScreen({super.key});

  @override
  State<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends State<AdminUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _lyricsController = TextEditingController();
  final _youtubeIdController = TextEditingController();

  int _selectedCategory = 0;
  int _selectedType = 0; // 0 = YouTube, 1 = Audio, 2 = Video
  PlatformFile? _selectedFile;
  String? _thumbnailUrl;
  bool _isUploading = false;
  bool _isAdmin = false;
  bool _isCheckingAuth = true; // ADD: Loading state for auth check

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  // UPDATED: Check admin status using your AuthProvider
  void _checkAdminStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      setState(() {
        _isAdmin =
            authProvider.isAuthenticated &&
            authProvider.hasAnyRole(['admin', 'super_admin', 'moderator']);
        _isCheckingAuth = false;
      });
    });
  }

  Future<void> _pickThumbnail() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || !_isAdmin) {
      _showError('Admin authentication required');
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // FIXED: Handle web vs mobile
        if (kIsWeb) {
          // For web, you might want to convert bytes to base64 or upload directly
          // Example: Convert to base64 for preview
          final bytes = file.bytes;
          if (bytes != null) {
            final base64String = base64Encode(bytes);
            setState(() {
              _thumbnailUrl =
                  'data:image/${file.extension};base64,$base64String';
            });
          }
        } else {
          setState(() {
            _thumbnailUrl = file.path;
          });
        }

        _showSuccess('Thumbnail selected (will be uploaded with song)');
      }
    } catch (e) {
      _showError('Failed to pick thumbnail: $e');
    }
  }

  // UPDATED: File picker with auth check
  Future<void> _pickMediaFile() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || !_isAdmin) {
      _showError('Admin authentication required');
      return;
    }

    FileType fileType = _selectedType == 1 ? FileType.audio : FileType.video;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: fileType,
        allowMultiple: false,
        allowCompression: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // Check file size (max 100MB)
        if (file.size > 100 * 1024 * 1024) {
          _showError('File size must be less than 100MB');
          return;
        }

        setState(() {
          _selectedFile = file;
        });
      }
    } catch (e) {
      _showError('Failed to pick file: $e');
    }
  }

  void _resetForm() {
    _titleController.clear();
    _artistController.clear();
    _lyricsController.clear();
    _youtubeIdController.clear();
    setState(() {
      _selectedFile = null;
      _thumbnailUrl = null;
      _selectedType = 0;
      _selectedCategory = 0;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _uploadSong() async {
    if (!_formKey.currentState!.validate()) return;

    // Double-check admin status
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || !_isAdmin) {
      _showError('Admin authentication required');
      return;
    }

    setState(() => _isUploading = true);

    try {
      final songData = {
        'title': _titleController.text,
        'artist': _artistController.text,
        'category': _selectedCategory,
        'lyrics': _lyricsController.text.isEmpty
            ? null
            : _lyricsController.text,
        'duration': 0,
        'allow_download': true,
      };

      if (_selectedType == 0) {
        // YouTube upload
        if (_youtubeIdController.text.isEmpty) {
          throw Exception('YouTube Video ID is required');
        }

        songData['videoId'] = _youtubeIdController.text;
        songData['thumbnail_url'] =
            _thumbnailUrl ??
            'https://img.youtube.com/vi/${_youtubeIdController.text}/hqdefault.jpg';

        await SongService.addYouTubeSong(songData);
      } else if (_selectedType == 1) {
        // Audio upload
        if (_selectedFile == null) {
          throw Exception('Please select an audio file');
        }

        songData['thumbnail_url'] =
            _thumbnailUrl ?? 'assets/images/worship_icon.jpeg';

        // Handle web vs mobile
        if (kIsWeb) {
          await SongService.uploadAudioFileWeb(
            fileBytes: _selectedFile!.bytes!,
            fileName: _selectedFile!.name,
            songData: songData,
          );
        } else {
          await SongService.uploadAudioFile(
            filePath: _selectedFile!.path!,
            songData: songData,
          );
        }
      } else if (_selectedType == 2) {
        // Video upload
        if (_selectedFile == null) {
          throw Exception('Please select a video file');
        }

        songData['thumbnail_url'] =
            _thumbnailUrl ?? 'assets/images/worship_icon.jpeg';

        // Handle web vs mobile
        if (kIsWeb) {
          await SongService.uploadVideoFileWeb(
            fileBytes: _selectedFile!.bytes!,
            fileName: _selectedFile!.name,
            songData: songData,
          );
        } else {
          await SongService.uploadVideoFile(
            filePath: _selectedFile!.path!,
            songData: songData,
          );
        }
      }

      _showSuccess('Song uploaded successfully!');
      _resetForm();
    } catch (e) {
      _showError('Failed to upload song: $e');
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking auth
    if (_isCheckingAuth) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Upload Worship Song'),
          backgroundColor: Colors.blue,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking permissions...'),
            ],
          ),
        ),
      );
    }

    // Show login required if not authenticated
    final authProvider = Provider.of<AuthProvider>(context);
    if (!authProvider.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Upload Worship Song'),
          backgroundColor: Colors.orange,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.login, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Login Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You need to be logged in to access this feature.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  // Navigate to login screen
                  Navigator.pushNamed(context, '/login');
                },
                icon: const Icon(Icons.login),
                label: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      );
    }

    // Show admin required if not admin
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Upload Worship Song'),
          backgroundColor: Colors.red,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.admin_panel_settings,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Admin Access Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Your role: ${authProvider.roles.join(', ')}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You need administrator privileges to upload songs.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Go back
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Show upload form for admins
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Worship Song'),
        backgroundColor: Colors.green[700],
        actions: [
          // User info badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                const Icon(Icons.person, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  authProvider.currentUser?.username ?? 'Admin',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showUploadHelp(context),
            tooltip: 'Upload Help',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Admin Badge with user info
              Consumer<AuthProvider>(
                builder: (context, auth, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      border: Border.all(color: Colors.green),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified,
                          color: Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Admin Mode - ${auth.currentUser?.username ?? 'User'}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Roles: ${auth.roles.join(', ')}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, size: 16),
                          onPressed: () {
                            auth.logout();
                            Navigator.pop(context);
                          },
                          tooltip: 'Logout',
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Media Type Selection
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Media Type *',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                            value: 0,
                            label: Text('YouTube'),
                            icon: Icon(Icons.video_library),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text('Audio File'),
                            icon: Icon(Icons.audio_file),
                          ),
                          ButtonSegment(
                            value: 2,
                            label: Text('Video File'),
                            icon: Icon(Icons.video_file),
                          ),
                        ],
                        selected: {_selectedType},
                        onSelectionChanged: _isUploading
                            ? null
                            : (selection) {
                                setState(() => _selectedType = selection.first);
                              },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // YouTube ID Input
              if (_selectedType == 0)
                TextFormField(
                  controller: _youtubeIdController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube Video ID *',
                    hintText: 'dQw4w9WgXcQ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'YouTube Video ID is required';
                    }
                    return null;
                  },
                ),

              // File Upload Section
              if (_selectedType == 1 || _selectedType == 2) ...[
                if (_selectedFile == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            _selectedType == 1
                                ? Icons.audio_file
                                : Icons.video_file,
                            size: 48,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selectedType == 1
                                ? 'Select Audio File'
                                : 'Select Video File',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _isUploading ? null : _pickMediaFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Choose File'),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_selectedFile != null)
                  Card(
                    color: Colors.green[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            _selectedType == 1
                                ? Icons.audio_file
                                : Icons.video_file,
                            color: Colors.green,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedFile!.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${(_selectedFile!.size / 1024 / 1024).toStringAsFixed(1)} MB',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isUploading ? null : _pickMediaFile,
                            icon: const Icon(Icons.edit),
                            tooltip: 'Change File',
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 20),

              // Basic Info
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Song Title *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Song title is required';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _artistController,
                decoration: const InputDecoration(
                  labelText: 'Artist *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Artist name is required';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Category
              DropdownButtonFormField<int>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('English Worship')),
                  DropdownMenuItem(value: 1, child: Text('African Worship')),
                ],
                onChanged: _isUploading
                    ? null
                    : (value) => setState(() => _selectedCategory = value!),
              ),

              const SizedBox(height: 16),

              // Thumbnail
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thumbnail Image',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _thumbnailUrl == null
                            ? 'Optional - Default will be used if not provided'
                            : 'Custom thumbnail selected',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _isUploading ? null : _pickThumbnail,
                        icon: const Icon(Icons.image),
                        label: Text(
                          _thumbnailUrl == null
                              ? 'Select Thumbnail'
                              : 'Change Thumbnail',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Lyrics (Optional)
              TextFormField(
                controller: _lyricsController,
                decoration: const InputDecoration(
                  labelText: 'Lyrics (Optional)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.lyrics),
                ),
                maxLines: 6,
              ),

              const SizedBox(height: 32),

              // Submit Button
              ElevatedButton(
                onPressed: _isUploading ? null : _uploadSong,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: _isUploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Uploading...'),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload),
                          SizedBox(width: 8),
                          Text('Upload Song'),
                        ],
                      ),
              ),

              if (_isUploading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                  'Uploading song... Please wait',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showUploadHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help, color: Colors.blue),
            SizedBox(width: 8),
            Text('Upload Guide'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpItem('YouTube Upload', [
                'Paste the Video ID from YouTube URL',
                'Example: For "https://youtu.be/dQw4w9WgXcQ" use "dQw4w9WgXcQ"',
                'Thumbnail will be auto-generated from YouTube',
              ]),
              const SizedBox(height: 12),
              _buildHelpItem('Audio Files', [
                'Supported formats: MP3, WAV, M4A, OGG',
                'Max file size: 100MB',
                'Add lyrics for better user experience',
              ]),
              const SizedBox(height: 12),
              _buildHelpItem('Video Files', [
                'Supported formats: MP4, MOV, AVI, MKV',
                'Max file size: 100MB',
                'Recommended: MP4 format for best compatibility',
              ]),
              const SizedBox(height: 12),
              _buildHelpItem('General Tips', [
                'Fill all required fields (*)',
                'Add lyrics to help users sing along',
                'Use high-quality thumbnails for better appearance',
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String title, List<String> points) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        ...points.map(
          (point) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• $point', style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _lyricsController.dispose();
    _youtubeIdController.dispose();
    super.dispose();
  }
}
