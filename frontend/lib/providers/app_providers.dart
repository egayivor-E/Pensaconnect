import 'dart:io';

import 'package:audioplayers_platform_interface/src/api/player_state.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart'
    hide PlayerState;
import '../models/worship_song.dart';
import 'package:pensaconnect/services/audio_service.dart';
import '../services/download_service.dart';
import '../services/song_service.dart';

class SongProvider with ChangeNotifier {
  List<WorshipSong> _songs = [];
  List<WorshipSong> _filteredSongs = [];
  int _selectedCategory = 0;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;

  // Getters
  List<WorshipSong> get songs => _songs;
  List<WorshipSong> get filteredSongs => _filteredSongs;
  int get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasError => _error != null;

  // Category names
  String get currentCategoryName =>
      _selectedCategory == 0 ? 'English' : 'African';

  // Helper getters for statistics
  int get totalSongs => _songs.length;
  int get englishSongs => _songs.where((song) => song.category == 0).length;
  int get africanSongs => _songs.where((song) => song.category == 1).length;
  int get youtubeSongs => _songs.where((song) => song.isYouTube).length;
  int get audioSongs => _songs.where((song) => song.isAudio).length;
  int get videoSongs => _songs.where((song) => song.isVideo).length;

  /// Load all songs from API
  Future<void> loadSongs() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _songs = await SongService.loadSongs();
      _applyFilters();
    } catch (e) {
      _error = 'Failed to load songs: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set category filter
  void setCategory(int category) {
    _selectedCategory = category;
    _applyFilters();
    notifyListeners();
  }

  /// Set search query
  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  /// Clear search query
  void clearSearch() {
    _searchQuery = '';
    _applyFilters();
    notifyListeners();
  }

  /// Apply all filters (category + search)
  void _applyFilters() {
    _filteredSongs = _songs.where((song) {
      final categoryMatch = song.category == _selectedCategory;
      final searchMatch =
          _searchQuery.isEmpty ||
          song.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          song.artist.toLowerCase().contains(_searchQuery.toLowerCase());
      return categoryMatch && searchMatch;
    }).toList();
  }

  /// Add new song
  Future<void> addSong(WorshipSong song) async {
    _songs.insert(0, song);
    _applyFilters();
    notifyListeners();
  }

  /// Update song
  Future<void> updateSong(String songId, WorshipSong updatedSong) async {
    final index = _songs.indexWhere((song) => song.id == songId);
    if (index != -1) {
      _songs[index] = updatedSong;
      _applyFilters();
      notifyListeners();
    }
  }

  /// Delete song
  Future<void> deleteSong(String songId) async {
    _songs.removeWhere((song) => song.id == songId);
    _applyFilters();
    notifyListeners();
  }

  /// Get song by ID
  WorshipSong? getSongById(String songId) {
    try {
      return _songs.firstWhere((song) => song.id == songId);
    } catch (e) {
      return null;
    }
  }

  /// Get songs by media type
  List<WorshipSong> getSongsByMediaType(String mediaType) {
    return _songs.where((song) => song.mediaType == mediaType).toList();
  }

  /// Get recently added songs
  List<WorshipSong> getRecentSongs({int count = 5}) {
    final sortedSongs = List<WorshipSong>.from(_songs)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sortedSongs.take(count).toList();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Refresh songs
  Future<void> refreshSongs() async {
    await loadSongs();
  }
}

class PlayerProvider with ChangeNotifier {
  final AudioService _audioService = AudioService();
  WorshipSong? _currentSong;
  List<WorshipSong> _playlist = [];
  int _currentIndex = 0;
  bool _isShuffling = false;
  bool _isRepeating = false;

  // Audio service delegates
  PlayerState get playerState => _audioService.playerState;
  Duration get position => _audioService.position;
  Duration get duration => _audioService.duration;
  bool get isPlaying => _audioService.isPlaying;
  bool get isLoading => _audioService.isLoading;
  String get formattedPosition => _audioService.formattedPosition;
  String get formattedDuration => _audioService.formattedDuration;
  double get progress => _audioService.progress;

  // Getters
  WorshipSong? get currentSong => _currentSong;
  List<WorshipSong> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isShuffling => _isShuffling;
  bool get isRepeating => _isRepeating;
  bool get hasNext => _currentIndex < _playlist.length - 1;
  bool get hasPrevious => _currentIndex > 0;

  // Media type helpers
  bool get isPlayingYouTube => _currentSong?.isYouTube ?? false;
  bool get isPlayingAudio => _currentSong?.isAudio ?? false;
  bool get isPlayingVideo => _currentSong?.isVideo ?? false;

  PlayerProvider() {
    // Listen to audio service changes
    _audioService.addListener(() {
      notifyListeners();
    });
  }

  /// Set playlist and play song
  void setPlaylist(List<WorshipSong> songs, int initialIndex) {
    _playlist = List.from(songs);
    _currentIndex = initialIndex;
    _currentSong = _playlist[_currentIndex];
    notifyListeners();
  }

  /// Play specific song
  Future<void> playSong(WorshipSong song) async {
    _currentSong = song;

    if (song.isAudio) {
      // For audio files, use the audio service
      final audioSource = song.audioUrl!;
      await _audioService.playAudio(
        songId: song.id,
        audioSource: audioSource,
        isLocal: false, // We'll handle offline later
      );
    }
    // For YouTube and video songs, the respective players handle playback
    notifyListeners();
  }

  /// Play next song in playlist
  Future<void> nextSong() async {
    if (hasNext) {
      _currentIndex++;
      await playSong(_playlist[_currentIndex]);
    } else if (isRepeating) {
      _currentIndex = 0;
      await playSong(_playlist[_currentIndex]);
    } else {
      // End of playlist, stop playback
      await stop();
    }
  }

  /// Play previous song in playlist
  Future<void> previousSong() async {
    if (hasPrevious) {
      _currentIndex--;
      await playSong(_playlist[_currentIndex]);
    } else if (isRepeating) {
      _currentIndex = _playlist.length - 1;
      await playSong(_playlist[_currentIndex]);
    }
  }

  /// Toggle shuffle
  void toggleShuffle() {
    _isShuffling = !_isShuffling;
    if (_isShuffling && _playlist.isNotEmpty) {
      final currentSongId = _currentSong?.id;
      _playlist.shuffle();
      if (currentSongId != null) {
        _currentIndex = _playlist.indexWhere(
          (song) => song.id == currentSongId,
        );
        if (_currentIndex == -1) _currentIndex = 0;
      }
    }
    notifyListeners();
  }

  /// Toggle repeat
  void toggleRepeat() {
    _isRepeating = !_isRepeating;
    notifyListeners();
  }

  // Audio service method delegates
  Future<void> play() async => await _audioService.resumeAudio();
  Future<void> pause() async => await _audioService.pauseAudio();
  Future<void> stop() async {
    await _audioService.stopAudio();
    _currentSong = null;
    notifyListeners();
  }

  Future<void> seek(Duration position) async =>
      await _audioService.seekAudio(position);
  Future<void> setVolume(double volume) async =>
      await _audioService.setVolume(volume);
  Future<void> togglePlayPause() async => await _audioService.togglePlayPause();

  /// Check if song is currently playing
  bool isSongPlaying(String songId) {
    return _currentSong?.id == songId && isPlaying;
  }

  /// Get the current media source for the player
  String? get currentMediaSource {
    if (_currentSong == null) return null;
    return _currentSong!.mediaSource;
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }
}

class DownloadProvider with ChangeNotifier {
  final DownloadService _downloadService = DownloadService();
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  final Map<String, String> _downloadErrors = {};
  final Map<String, String?> _localPaths = {};

  // Getters
  double getDownloadProgress(String songId) => _downloadProgress[songId] ?? 0.0;
  bool isDownloading(String songId) => _isDownloading[songId] ?? false;
  String? getDownloadError(String songId) => _downloadErrors[songId];
  bool isDownloaded(String songId) {
    return _localPaths[songId] != null;
  }

  /// Load initial downloaded songs (from first provider)
  Future<void> loadDownloadedSongs(List<WorshipSong> allSongs) async {
    for (final song in allSongs) {
      await isSongDownloaded(song); // This will cache the result
    }
    notifyListeners();
  }

  /// Download song with progress tracking
  Future<void> downloadSong(WorshipSong song) async {
    final songId = song.id;

    // Check if song is downloadable
    if (!song.allowDownload) {
      _downloadErrors[songId] = 'This song is not available for download';
      notifyListeners();
      return;
    }

    _isDownloading[songId] = true;
    _downloadProgress[songId] = 0.0;
    _downloadErrors.remove(songId);
    notifyListeners();

    try {
      final filePath = await _downloadService.downloadSongWithProgress(
        song,
        onProgress: (progress) {
          _downloadProgress[songId] = progress;
          notifyListeners();
        },
        onComplete: (filePath) {
          _isDownloading.remove(songId);
          _downloadProgress.remove(songId);
          _downloadErrors.remove(songId);

          // Increment download count on server
          SongService.incrementDownloadCount(songId);

          notifyListeners();
        },
        onError: (error) {
          _isDownloading.remove(songId);
          _downloadProgress.remove(songId);
          _downloadErrors[songId] = error;
          notifyListeners();
        },
      );
    } catch (e) {
      _isDownloading.remove(songId);
      _downloadProgress.remove(songId);
      _downloadErrors[songId] = e.toString();
      notifyListeners();
    }
  }

  /// Cancel download
  void cancelDownload(String songId) {
    _downloadService.cancelDownload(songId);
    _isDownloading.remove(songId);
    _downloadProgress.remove(songId);
    _downloadErrors.remove(songId);
    notifyListeners();
  }

  /// Clear download error
  void clearError(String songId) {
    _downloadErrors.remove(songId);
    notifyListeners();
  }

  /// Check if song is downloaded

  Future<bool> isSongDownloaded(WorshipSong song) async {
    final songId = song.id;

    // Check cache first
    if (_localPaths.containsKey(songId)) {
      return _localPaths[songId] != null;
    }

    // Check filesystem
    final filePath = await _downloadService.getLocalFilePath(song);
    _localPaths[songId] = filePath;
    return filePath != null;
  }

  /// Get local file path
  Future<String?> getLocalFilePath(WorshipSong song) async {
    final songId = song.id;

    // Check cache first
    if (_localPaths.containsKey(songId) && _localPaths[songId] != null) {
      return _localPaths[songId];
    }

    // Check filesystem
    final filePath = await _downloadService.getLocalFilePath(song);
    _localPaths[songId] = filePath;
    return filePath;
  }

  /// Delete downloaded song
  Future<bool> deleteDownloadedSong(WorshipSong song) async {
    final success = await _downloadService.deleteDownloadedSong(song);
    notifyListeners();
    return success;
  }

  /// Get all downloaded songs - UPDATED: Now returns List<WorshipSong>
  Future<List<WorshipSong>> getDownloadedSongs(
    List<WorshipSong> allSongs,
  ) async {
    return await _downloadService.getDownloadedSongs(allSongs);
  }

  /// Get downloaded song file paths - NEW: Returns List<String> of file paths
  Future<List<String>> getDownloadedSongPaths() async {
    try {
      final dir = await _downloadService.getDownloadsDirectory();
      if (await dir.exists()) {
        final files = await dir.list().toList();
        return files.whereType<File>().map((file) => file.path).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get total download size - UPDATED: Now requires song list
  Future<String> getTotalDownloadSizeFormatted(
    List<WorshipSong> allSongs,
  ) async {
    final totalBytes = await _downloadService.getTotalDownloadSize(allSongs);
    if (totalBytes < 1024) {
      return '$totalBytes B';
    } else if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Get downloadable songs count
  int getDownloadableSongsCount(List<WorshipSong> songs) {
    return songs.where((song) => song.allowDownload).length;
  }

  /// Get songs by download status
  Map<String, List<WorshipSong>> getSongsByDownloadStatus(
    List<WorshipSong> songs,
  ) {
    final downloaded = <WorshipSong>[];
    final downloading = <WorshipSong>[];
    final available = <WorshipSong>[];

    for (final song in songs) {
      if (isDownloading(song.id)) {
        downloading.add(song);
      } else if (song.allowDownload) {
        available.add(song);
      }
    }

    return {
      'downloaded': downloaded,
      'downloading': downloading,
      'available': available,
    };
  }

  /// NEW: Get download statistics
  Future<Map<String, dynamic>> getDownloadStats(
    List<WorshipSong> allSongs,
  ) async {
    return await _downloadService.getDownloadStats(allSongs);
  }

  /// NEW: Get downloaded songs count
  Future<int> getDownloadedSongsCount(List<WorshipSong> allSongs) async {
    final downloaded = await getDownloadedSongs(allSongs);
    return downloaded.length;
  }

  /// NEW: Clear all downloads
  Future<void> clearAllDownloads() async {
    await _downloadService.clearAllDownloads();
    notifyListeners();
  }
}
