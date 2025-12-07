import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/worship_song.dart';
import '../widgets/song_card.dart';
import '../providers/app_providers.dart';

class WorshipScreen extends StatefulWidget {
  const WorshipScreen({super.key});

  @override
  State<WorshipScreen> createState() => _WorshipScreenState();
}

class _WorshipScreenState extends State<WorshipScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearchBar = false;
  int _currentView = 0; // 0 = Library, 1 = Categories, 2 = Recent

  @override
  void initState() {
    super.initState();
    // Delay provider access until after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  void _initializeData() {
    final songProvider = Provider.of<SongProvider>(context, listen: false);
    if (songProvider.songs.isEmpty) {
      songProvider.loadSongs();
    }
  }

  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (!_showSearchBar) {
        _searchController.clear();
        final songProvider = Provider.of<SongProvider>(context, listen: false);
        songProvider.clearSearch();
      }
    });
  }

  void _performSearch(String query) {
    final songProvider = Provider.of<SongProvider>(context, listen: false);
    songProvider.setSearchQuery(query);
  }

  void _clearSearch() {
    _searchController.clear();
    final songProvider = Provider.of<SongProvider>(context, listen: false);
    songProvider.clearSearch();
    setState(() {
      _showSearchBar = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
          tooltip: 'Back to Home',
        ),
        title: _showSearchBar
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search songs or artists...',
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearSearch,
                  ),
                ),
                onChanged: _performSearch,
                style: theme.textTheme.titleMedium,
              )
            : Text(
                'Praise & Worship',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          // Search toggle button
          IconButton(
            icon: Icon(_showSearchBar ? Icons.close : Icons.search),
            onPressed: _toggleSearchBar,
            tooltip: _showSearchBar ? 'Close Search' : 'Search Songs',
          ),
          // Upload button
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/worship/upload'),
            tooltip: 'Upload Song',
          ),
          // Refresh button with loading state
          Consumer<SongProvider>(
            builder: (context, songProvider, child) {
              return IconButton(
                icon: songProvider.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: songProvider.isLoading
                    ? null
                    : () => songProvider.refreshSongs(),
                tooltip: 'Refresh Songs',
              );
            },
          ),
        ],
      ),
      body: Consumer<SongProvider>(
        builder: (context, songProvider, child) {
          final filteredSongs = songProvider.filteredSongs;
          final hasSongs = songProvider.songs.isNotEmpty;
          final hasSearchResults = filteredSongs.isNotEmpty;
          final isSearching = songProvider.searchQuery.isNotEmpty;

          // If no songs or searching, show the song list view
          if (!hasSongs || isSearching || _currentView == 0) {
            return _buildSongListView(
              songProvider,
              filteredSongs,
              theme,
              isSearching,
              hasSongs,
              hasSearchResults,
            );
          }

          // Otherwise show the worship home dashboard
          return _buildWorshipHome(songProvider, theme);
        },
      ),
      floatingActionButton: _currentView == 0
          ? FloatingActionButton(
              onPressed: () => context.push('/worship/upload'),
              child: const Icon(Icons.add),
              tooltip: 'Upload New Song',
            )
          : null,
      bottomNavigationBar: Consumer<SongProvider>(
        builder: (context, songProvider, child) {
          final hasSongs = songProvider.songs.isNotEmpty;
          final isSearching = songProvider.searchQuery.isNotEmpty;

          return hasSongs && !isSearching
              ? BottomNavigationBar(
                  currentIndex: _currentView,
                  onTap: (index) {
                    setState(() {
                      _currentView = index;
                    });
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.library_music),
                      label: 'Songs',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.category),
                      label: 'Categories',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.history),
                      label: 'Recent',
                    ),
                  ],
                )
              : const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildWorshipHome(SongProvider songProvider, ThemeData theme) {
    final englishSongs = songProvider.songs
        .where((s) => s.category == 0)
        .toList();
    final africanSongs = songProvider.songs
        .where((s) => s.category == 1)
        .toList();
    final recentSongs = songProvider.getRecentSongs(count: 5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.music_note,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome to Worship',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${songProvider.songs.length} songs available for worship',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Quick Stats
          Text(
            'Library Overview',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  'Total Songs',
                  songProvider.totalSongs.toString(),
                  Icons.library_music,
                  Colors.deepPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  'English',
                  songProvider.englishSongs.toString(),
                  Icons.language,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  'African',
                  songProvider.africanSongs.toString(),
                  Icons.public,
                  Colors.green,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Media Type Stats
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  'YouTube',
                  songProvider.youtubeSongs.toString(),
                  Icons.video_library,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  'Audio',
                  songProvider.audioSongs.toString(),
                  Icons.audio_file,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  'Video',
                  songProvider.videoSongs.toString(),
                  Icons.video_file,
                  Colors.purple,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Quick Access Categories
          Text(
            'Worship Categories',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Card(
                  elevation: 2,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _currentView = 0;
                        songProvider.setCategory(0);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.language,
                              color: Colors.blue,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'English Worship',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${englishSongs.length} songs',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  elevation: 2,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _currentView = 0;
                        songProvider.setCategory(1);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.public,
                              color: Colors.green,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'African Worship',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${africanSongs.length} songs',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Recently Added
          Text(
            'Recently Added',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (recentSongs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.music_note,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No songs yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    ...recentSongs.map(
                      (song) => ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            song.thumbnailUrl,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 50,
                                height: 50,
                                color: Colors.grey[300],
                                child: Icon(
                                  Icons.music_note,
                                  color: Colors.grey[500],
                                ),
                              );
                            },
                          ),
                        ),
                        title: Text(
                          song.title,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song.artist,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          Icons.play_arrow,
                          color: theme.colorScheme.primary,
                        ),
                        onTap: () => context.push(
                          '/worship/player',
                          extra: {
                            'songs': [song],
                            'initialIndex': 0,
                          },
                        ),
                      ),
                    ),
                  if (recentSongs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _currentView = 0;
                          });
                        },
                        child: const Text('View All Songs'),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Quick Actions
          Text(
            'Quick Actions',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Card(
                  elevation: 2,
                  child: InkWell(
                    onTap: () => context.push('/worship/upload'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.add_circle, color: Colors.green, size: 32),
                          const SizedBox(height: 8),
                          const Text(
                            'Add Song',
                            style: TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Upload new worship',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  elevation: 2,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _currentView = 0;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.library_music,
                            color: Colors.blue,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'All Songs',
                            style: TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Browse library',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSongListView(
    SongProvider songProvider,
    List<WorshipSong> songs,
    ThemeData theme,
    bool isSearching,
    bool hasSongs,
    bool hasSearchResults,
  ) {
    return Column(
      children: [
        // Category Filter (only show in song list view)
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('English'),
                icon: Icon(Icons.language),
              ),
              ButtonSegment(
                value: 1,
                label: Text('African'),
                icon: Icon(Icons.public),
              ),
            ],
            selected: {songProvider.selectedCategory},
            onSelectionChanged: (selection) {
              songProvider.setCategory(selection.first);
            },
          ),
        ),

        // Search results indicator
        if (isSearching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Search: "${songProvider.searchQuery}"',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                TextButton(onPressed: _clearSearch, child: const Text('Clear')),
              ],
            ),
          ),

        // Loading indicator
        if (songProvider.isLoading && !hasSongs)
          const LinearProgressIndicator(),

        // Stats and Info Bar
        if (hasSongs)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  isSearching
                      ? '${songs.length} result${songs.length == 1 ? '' : 's'}'
                      : '${songs.length} song${songs.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const Spacer(),
                if (!isSearching)
                  Text(
                    songProvider.selectedCategory == 0
                        ? 'English Worship'
                        : 'African Worship',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),

        // Error Message
        if (songProvider.hasError)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[100]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    songProvider.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.red[700],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => songProvider.clearError(),
                ),
              ],
            ),
          ),

        // Song List or Empty State
        Expanded(
          child: _buildSongListContent(
            songProvider,
            songs,
            theme,
            isSearching,
            hasSongs,
            hasSearchResults,
          ),
        ),
      ],
    );
  }

  Widget _buildSongListContent(
    SongProvider songProvider,
    List<WorshipSong> songs,
    ThemeData theme,
    bool isSearching,
    bool hasSongs,
    bool hasSearchResults,
  ) {
    // Loading state
    if (songProvider.isLoading && songProvider.songs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading worship songs...'),
          ],
        ),
      );
    }

    // Empty state
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              isSearching
                  ? 'No songs found for "${songProvider.searchQuery}"'
                  : 'No songs available',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Try a different search term'
                  : 'Tap + to add the first worship song',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (!isSearching) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.push('/worship/upload'),
                icon: const Icon(Icons.add),
                label: const Text('Add First Song'),
              ),
            ],
          ],
        ),
      );
    }

    // Song list with refresh
    return RefreshIndicator(
      onRefresh: () => songProvider.refreshSongs(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return Consumer<DownloadProvider>(
            builder: (context, downloadProvider, child) {
              return SongCard(
                song: song,
                onTap: () => context.push(
                  '/worship/player',
                  extra: {'songs': songs, 'initialIndex': index},
                ),
                isDownloading: downloadProvider.isDownloading(song.id),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
