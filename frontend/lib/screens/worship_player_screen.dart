import 'package:flutter/material.dart';
import '../models/worship_song.dart';
import '../widgets/universal_youtube_player.dart';

class WorshipPlayerScreen extends StatefulWidget {
  final List<WorshipSong> songs;
  final int initialIndex;
  final bool isOffline;
  final String? offlineFilePath;

  const WorshipPlayerScreen({
    super.key,
    required this.songs,
    required this.initialIndex,
    this.isOffline = false,
    this.offlineFilePath,
  });

  @override
  State<WorshipPlayerScreen> createState() => _WorshipPlayerScreenState();
}

class _WorshipPlayerScreenState extends State<WorshipPlayerScreen> {
  late int _currentIndex;
  bool _showLyrics = false;
  bool _showControls = true;

  WorshipSong get currentSong => widget.songs[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _playNext() {
    if (_currentIndex < widget.songs.length - 1) {
      setState(() => _currentIndex++);
    } else {
      setState(() => _currentIndex = 0);
    }
  }

  void _playPrev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    } else {
      setState(() => _currentIndex = widget.songs.length - 1);
    }
  }

  void _toggleLyrics() {
    setState(() => _showLyrics = !_showLyrics);
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    return Scaffold(
      appBar: isLandscape
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentSong.title,
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    currentSong.artist,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    _showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
                  ),
                  onPressed: _toggleLyrics,
                  tooltip: 'Toggle Lyrics',
                ),
                if (currentSong.isAvailableOffline)
                  const Icon(Icons.download_done, color: Colors.green),
              ],
            ),
      body: SafeArea(
        child: isLandscape
            ? _buildLandscapeLayout(theme, mediaQuery)
            : _buildPortraitLayout(theme, mediaQuery),
      ),
    );
  }

  // ✅ PORTRAIT LAYOUT - Optimized for mobile phones
  Widget _buildPortraitLayout(ThemeData theme, MediaQueryData mediaQuery) {
    return Column(
      children: [
        // Media Player - Flexible height based on content
        Flexible(
          flex: 3,
          fit: FlexFit.tight,
          child: UniversalYoutubePlayer(
            song: currentSong,
            autoPlay: true,
            aspectRatio: currentSong.isAudio ? 1 : 16 / 9,
          ),
        ),

        // Song Info & Controls - Fixed but flexible
        Container(
          constraints: BoxConstraints(
            minHeight: 80,
            maxHeight: mediaQuery.size.height * 0.25, // Max 25% of screen
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Song Title
              Text(
                currentSong.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Artist Name
              Text(
                currentSong.artist,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),

              // Navigation Controls
              if (_showControls)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 32),
                      onPressed: _playPrev,
                      tooltip: 'Previous Song',
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 32),
                      onPressed: _playNext,
                      tooltip: 'Next Song',
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Lyrics or Playlist Info - Takes remaining space
        if (_showLyrics)
          Expanded(flex: 2, child: _buildLyricsPanel(theme))
        else
          // Playlist progress when lyrics are hidden
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_currentIndex + 1} of ${widget.songs.length}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  'Swipe down to close',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ✅ LANDSCAPE LAYOUT - Optimized for tablets and landscape mode
  Widget _buildLandscapeLayout(ThemeData theme, MediaQueryData mediaQuery) {
    return Row(
      children: [
        // Media Player - Takes 60% of width
        Expanded(
          flex: 6,
          child: UniversalYoutubePlayer(
            song: currentSong,
            autoPlay: true,
            aspectRatio: currentSong.isAudio ? 1 : 16 / 9,
          ),
        ),

        // Side Panel - Takes 40% of width
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.1),
              border: Border(left: BorderSide(color: theme.dividerColor)),
            ),
            child: Column(
              children: [
                // Song Info Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentSong.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentSong.artist,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),

                // Controls
                if (_showControls)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 32),
                          onPressed: _playPrev,
                          tooltip: 'Previous Song',
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.skip_next, size: 32),
                          onPressed: _playNext,
                          tooltip: 'Next Song',
                        ),
                      ],
                    ),
                  ),

                // Lyrics or Playlist Info
                Expanded(
                  child: _showLyrics
                      ? _buildLyricsPanel(theme)
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${_currentIndex + 1} of ${widget.songs.length}',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap lyrics icon to view song lyrics',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.5),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                ),

                // Bottom Info Bar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          _showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
                        ),
                        onPressed: _toggleLyrics,
                        tooltip: 'Toggle Lyrics',
                      ),
                      if (currentSong.isAvailableOffline)
                        const Icon(Icons.download_done, color: Colors.green),
                      Text(
                        'Swipe to close',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ✅ REUSABLE LYRICS PANEL
  Widget _buildLyricsPanel(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: currentSong.lyrics != null && currentSong.lyrics!.isNotEmpty
          ? SingleChildScrollView(
              child: Text(
                currentSong.lyrics!,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                textAlign: TextAlign.center,
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 48,
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No lyrics available',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enjoy the music!',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
