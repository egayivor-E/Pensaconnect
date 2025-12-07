import '../models/worship_song.dart';

// Fallback hardcoded songs for offline/demo use
List<WorshipSong> worshipSongs = [
  WorshipSong(
    id: '1',
    title: 'What A Beautiful Name',
    artist: 'Hillsong Worship',
    videoId: 'nQWFzMvCfLE',
    thumbnailUrl: 'https://img.youtube.com/vi/nQWFzMvCfLE/maxresdefault.jpg',
    category: 0, // English
    mediaType: 'youtube', // UPDATED: Use mediaType instead of isYouTube
    lyrics: '''
You were the Word at the beginning
One with God the Lord Most High
Your hidden glory in creation
Now revealed in You our Christ

What a beautiful Name it is
What a beautiful Name it is
The Name of Jesus Christ my King

What a beautiful Name it is
Nothing compares to this
What a beautiful Name it is
The Name of Jesus
''',
    duration: 372, // 6:12 minutes
    fileSize: 0,
    allowDownload: true, // UPDATED: Use allowDownload instead of isDownloadable
    downloadCount: 0,
    createdAt: DateTime(2024, 1, 15),
  ),
  WorshipSong(
    id: '2',
    title: 'Goodness of God',
    artist: 'Bethel Music',
    videoId: '2hOsS2SiIe4',
    thumbnailUrl: 'https://img.youtube.com/vi/2hOsS2SiIe4/maxresdefault.jpg',
    category: 0, // English
    mediaType: 'youtube', // UPDATED
    lyrics: '''
I love You, Lord
For Your mercy never fails me
All my days, I've been held in Your hands
From the moment that I wake up
Until I lay my head
Oh, I will sing of the goodness of God
''',
    duration: 314, // 5:14 minutes
    fileSize: 0,
    allowDownload: true,
    downloadCount: 0,
    createdAt: DateTime(2024, 1, 10),
  ),
  WorshipSong(
    id: '3',
    title: 'Way Maker',
    artist: 'Sinach',
    videoId: 'XeroO9y2Lc0',
    thumbnailUrl: 'https://img.youtube.com/vi/XeroO9y2Lc0/maxresdefault.jpg',
    category: 1, // African
    mediaType: 'youtube', // UPDATED
    lyrics: '''
You are here, moving in our midst
You are here, working in this place

You are way maker, miracle worker
Promise keeper, light in the darkness
My God, that is who You are
''',
    duration: 543, // 9:03 minutes
    fileSize: 0,
    allowDownload: true,
    downloadCount: 0,
    createdAt: DateTime(2024, 1, 5),
  ),
  WorshipSong(
    id: '4',
    title: 'Yesu Munyenyezi',
    artist: 'Wilson Bugembe',
    videoId: 'abc123def', // Example ID
    thumbnailUrl: 'assets/images/worship_icon.jpeg',
    category: 1, // African
    mediaType: 'youtube', // UPDATED
    lyrics: '''
Yesu Munyenyezi, gwe ow'omunda
Nkutendereza, nkwebaza
Omusa gwo gunsiima, talina bwo gugera
''',
    duration: 420, // 7:00 minutes
    fileSize: 0,
    allowDownload: true,
    downloadCount: 0,
    createdAt: DateTime(2024, 1, 1),
  ),
  WorshipSong(
    id: '5',
    title: 'Oceans (Where Feet May Fail)',
    artist: 'Hillsong UNITED',
    videoId: 'FBJJJkiRukY',
    thumbnailUrl: 'https://img.youtube.com/vi/FBJJJkiRukY/maxresdefault.jpg',
    category: 0, // English
    mediaType: 'youtube', // UPDATED
    lyrics: '''
You call me out upon the waters
The great unknown where feet may fail
And there I find You in the mystery
In oceans deep my faith will stand
''',
    duration: 537, // 8:57 minutes
    fileSize: 0,
    allowDownload: true, // UPDATED
    downloadCount: 15,
    createdAt: DateTime(2024, 1, 20),
  ),
  WorshipSong(
    id: '6',
    title: 'Test Audio Song',
    artist: 'Local Artist',
    audioUrl: 'https://example.com/audio/test.mp3',
    thumbnailUrl: 'assets/images/worship_icon.jpeg',
    category: 0, // English
    mediaType: 'audio', // UPDATED: Use mediaType instead of isAudio
    lyrics: 'This is a test audio file for demonstration.',
    duration: 180, // 3:00 minutes
    fileSize: 5242880, // 5MB
    allowDownload: true, // UPDATED
    downloadCount: 8,
    createdAt: DateTime(2024, 1, 25),
  ),
  // NEW: Added video song example
  WorshipSong(
    id: '7',
    title: 'Worship Session Live',
    artist: 'Local Church',
    videoUrl: 'https://example.com/videos/worship-live.mp4',
    thumbnailUrl: 'assets/images/worship_icon.jpeg',
    category: 1, // African
    mediaType: 'video', // NEW: Video type
    lyrics: 'Live worship session from our church service.',
    duration: 720, // 12:00 minutes
    fileSize: 104857600, // 100MB
    allowDownload: false, // Large file, no download
    downloadCount: 0,
    createdAt: DateTime(2024, 1, 30),
  ),
  // NEW: Added another audio song
  WorshipSong(
    id: '8',
    title: 'Amazing Grace',
    artist: 'Traditional',
    audioUrl: 'https://example.com/audio/amazing-grace.mp3',
    thumbnailUrl: 'assets/images/worship_icon.jpeg',
    category: 0, // English
    mediaType: 'audio',
    lyrics: '''
Amazing grace, how sweet the sound
That saved a wretch like me
I once was lost, but now I'm found
Was blind, but now I see
''',
    duration: 240, // 4:00 minutes
    fileSize: 3145728, // 3MB
    allowDownload: true,
    downloadCount: 25,
    createdAt: DateTime(2024, 2, 1),
  ),
];

// Helper functions
WorshipSong? getSongById(String id) {
  try {
    return worshipSongs.firstWhere((song) => song.id == id);
  } catch (e) {
    return null;
  }
}

List<WorshipSong> getSongsByCategory(int category) {
  return worshipSongs.where((song) => song.category == category).toList();
}

List<WorshipSong> getSongsByMediaType(String mediaType) {
  return worshipSongs.where((song) => song.mediaType == mediaType).toList();
}

List<WorshipSong> getDownloadableSongs() {
  return worshipSongs.where((song) => song.allowDownload).toList();
}

List<WorshipSong> getRecentSongs({int count = 5}) {
  final sortedSongs = List<WorshipSong>.from(worshipSongs)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sortedSongs.take(count).toList();
}

List<WorshipSong> searchSongs(String query) {
  if (query.isEmpty) return worshipSongs;

  final lowercaseQuery = query.toLowerCase();
  return worshipSongs.where((song) {
    return song.title.toLowerCase().contains(lowercaseQuery) ||
        song.artist.toLowerCase().contains(lowercaseQuery) ||
        (song.lyrics?.toLowerCase().contains(lowercaseQuery) ?? false);
  }).toList();
}

// NEW: Statistics helper
Map<String, dynamic> getLibraryStats() {
  final total = worshipSongs.length;
  final english = worshipSongs.where((s) => s.category == 0).length;
  final african = worshipSongs.where((s) => s.category == 1).length;
  final youtube = worshipSongs.where((s) => s.isYouTube).length;
  final audio = worshipSongs.where((s) => s.isAudio).length;
  final video = worshipSongs.where((s) => s.isVideo).length;
  final downloadable = worshipSongs.where((s) => s.allowDownload).length;
  final totalDownloads = worshipSongs.fold(
    0,
    (sum, song) => sum + song.downloadCount,
  );

  return {
    'total': total,
    'english': english,
    'african': african,
    'youtube': youtube,
    'audio': audio,
    'video': video,
    'downloadable': downloadable,
    'totalDownloads': totalDownloads,
  };
}

// NEW: Get popular songs by download count
List<WorshipSong> getPopularSongs({int count = 5}) {
  final sortedSongs = List<WorshipSong>.from(worshipSongs)
    ..sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
  return sortedSongs.take(count).toList();
}

// NEW: Get songs for home dashboard
Map<String, List<WorshipSong>> getDashboardSongs() {
  return {
    'recent': getRecentSongs(count: 3),
    'popular': getPopularSongs(count: 3),
    'english': getSongsByCategory(0).take(2).toList(),
    'african': getSongsByCategory(1).take(2).toList(),
  };
}
