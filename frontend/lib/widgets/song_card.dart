import 'package:flutter/material.dart';
import 'package:pensaconnect/providers/app_providers.dart';
import 'package:provider/provider.dart'; // ADD THIS
import '../models/worship_song.dart';

class SongCard extends StatelessWidget {
  final WorshipSong song;
  final VoidCallback onTap;
  final VoidCallback? onDownload; // Keep for backward compatibility
  final bool isDownloading; // Keep for backward compatibility

  const SongCard({
    super.key,
    required this.song,
    required this.onTap,
    this.onDownload,
    this.isDownloading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloadProvider = Provider.of<DownloadProvider>(
      context,
      listen: true,
    ); // ADD THIS

    // Get download state from provider
    final isActuallyDownloading = downloadProvider.isDownloading(song.id);
    final downloadProgress = downloadProvider.getDownloadProgress(song.id);
    final isDownloaded = downloadProvider.isDownloaded(song.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              FadeInImage.assetNetwork(
                placeholder: 'assets/images/worship_icon.jpeg',
                image: song.thumbnailUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                imageErrorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 60,
                    height: 60,
                    color: Colors.grey[300],
                    alignment: Alignment.center,
                    child: const Icon(Icons.music_note, color: Colors.black54),
                  );
                },
              ),
              // Offline indicator - Updated to use provider state
              if (isDownloaded)
                Positioned(
                  top: 4,
                  left: 4,
                  child: GestureDetector(
                    onTap: () =>
                        _showDownloadOptions(context, song, downloadProvider),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.download_done,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        title: Text(
          song.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              song.artist,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            // Media type indicator
            if (song.isAudio)
              Text(
                'Audio',
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.blue),
              )
            else if (song.isVideo && !song.isYouTube)
              Text(
                'Video',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.purple,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Download button - Updated to use provider
            _buildDownloadButton(
              context,
              song,
              downloadProvider,
              isActuallyDownloading,
              downloadProgress,
              isDownloaded,
            ),
            Icon(Icons.play_arrow, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  // NEW: Build appropriate download button
  Widget _buildDownloadButton(
    BuildContext context,
    WorshipSong song,
    DownloadProvider downloadProvider,
    bool isDownloading,
    double progress,
    bool isDownloaded,
  ) {
    // If already downloaded, show green checkmark with options
    if (isDownloaded) {
      return IconButton(
        icon: const Icon(Icons.download_done, color: Colors.green),
        iconSize: 20,
        onPressed: () => _showDownloadOptions(context, song, downloadProvider),
        tooltip: 'Downloaded - Tap for options',
      );
    }

    // If downloading, show progress indicator
    if (isDownloading) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(value: progress, strokeWidth: 2),
            if (progress > 0)
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      );
    }

    // If not downloaded and not downloading, show download button if allowed
    if (song.allowDownload) {
      return IconButton(
        icon: const Icon(Icons.download),
        iconSize: 20,
        onPressed: () => _handleDownload(context, song, downloadProvider),
        tooltip: 'Download for offline',
      );
    }

    // If downloads not allowed, show disabled icon
    return IconButton(
      icon: const Icon(Icons.download, color: Colors.grey),
      iconSize: 20,
      onPressed: null,
      tooltip: 'Download not available',
    );
  }

  // NEW: Handle download with error handling
  void _handleDownload(
    BuildContext context,
    WorshipSong song,
    DownloadProvider downloadProvider,
  ) async {
    try {
      await downloadProvider.downloadSong(song);

      // Show success snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${song.title} downloaded successfully!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Show error snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // NEW: Show download options for downloaded songs
  void _showDownloadOptions(
    BuildContext context,
    WorshipSong song,
    DownloadProvider downloadProvider,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info, color: Colors.blue),
                title: const Text('Downloaded'),
                subtitle: Text('${song.title} is available offline'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.play_circle_filled,
                  color: Colors.green,
                ),
                title: const Text('Play Offline'),
                onTap: () {
                  Navigator.pop(context);
                  _playOffline(context, song, downloadProvider);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Download'),
                onTap: () async {
                  Navigator.pop(context);
                  final confirmed = await _confirmDelete(context, song);
                  if (confirmed) {
                    await downloadProvider.deleteDownloadedSong(song);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${song.title} deleted from device'),
                        backgroundColor: Colors.orange,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.grey),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  // NEW: Play offline file
  void _playOffline(
    BuildContext context,
    WorshipSong song,
    DownloadProvider downloadProvider,
  ) async {
    final filePath = await downloadProvider.getLocalFilePath(song);

    if (filePath != null && filePath.isNotEmpty) {
      // Navigate to player with offline flag
      // You'll need to update your player screen to handle offline files
      Navigator.pushNamed(
        context,
        '/worship/player',
        arguments: {
          'songs': [song],
          'initialIndex': 0,
          'isOffline': true,
          'filePath': filePath,
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline file not found. Please download again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // NEW: Confirm delete dialog
  Future<bool> _confirmDelete(BuildContext context, WorshipSong song) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Download?'),
            content: Text('This will remove "${song.title}" from your device.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}
