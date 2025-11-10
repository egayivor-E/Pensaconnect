import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WorshipScreen extends StatefulWidget {
  const WorshipScreen({super.key});

  @override
  State<WorshipScreen> createState() => _WorshipScreenState();
}

class _WorshipScreenState extends State<WorshipScreen> {
  int _selectedCategory = 0;

  final List<Map<String, dynamic>> _songs = [
    {
      'title': 'Goodness of God',
      'artist': 'Bethel Music',
      'videoId': 'B8gLsbvSn0E',
      'category': 0,
    },
    {
      'title': 'What a Beautiful Name',
      'artist': 'Hillsong Worship',
      'videoId': 'nQWFzMvCfLE',
      'category': 0,
    },
    {
      'title': 'Way Maker',
      'artist': 'Sinach',
      'videoId': 'XQan9L3yXjc',
      'category': 0,
    },
    {
      'title': 'African Praise Medley',
      'artist': 'Various Artists',
      'videoId': 'PLvQ3QZf5zTkX9XqH6JMsX8G4Z3X6Y6Y6Y',
      'category': 1,
    },
    {
      'title': 'Yahweh',
      'artist': 'Nathaniel Bassey',
      'videoId': 'PLvQ3QZf5zTkX9XqH6JMsX8G4Z3X6Y6Y6Y',
      'category': 1,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredSongs = _songs
        .where((song) => song['category'] == _selectedCategory)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Praise & Worship',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('English')),
                ButtonSegment(value: 1, label: Text('African')),
              ],
              selected: {_selectedCategory},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() {
                  _selectedCategory = newSelection.first;
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: filteredSongs.length,
              itemBuilder: (context, index) {
                final song = filteredSongs[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        'https://img.youtube.com/vi/${song['videoId']}/0.jpg',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey[300],
                          child: const Icon(Icons.music_note),
                        ),
                      ),
                    ),
                    title: Text(
                      song['title'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      song['artist'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    trailing: Icon(
                      Icons.play_arrow,
                      color: theme.colorScheme.primary,
                    ),
                    onTap: () {
                      final songIndex = filteredSongs.indexOf(song);
                      context.push(
                        '/worship/player',
                        extra: {
                          'songs': filteredSongs,
                          'initialIndex': songIndex,
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
