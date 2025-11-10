import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class WorshipPlayerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> songs;
  final int initialIndex;

  const WorshipPlayerScreen({
    super.key,
    required this.songs,
    required this.initialIndex,
  });

  @override
  State<WorshipPlayerScreen> createState() => _WorshipPlayerScreenState();
}

class _WorshipPlayerScreenState extends State<WorshipPlayerScreen> {
  late YoutubePlayerController _controller;
  late int _currentIndex;
  bool _isPlaying = false;
  bool _showControls = true;
  late ScrollController _scrollController;
  double _lastOffset = 0;

  Map<String, dynamic> get _currentSong => widget.songs[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _scrollController = ScrollController()..addListener(_scrollListener);

    if (!kIsWeb) {
      _initController(_currentSong['videoId']);
    }
  }

  void _scrollListener() {
    final offset = _scrollController.offset;
    if (offset > _lastOffset && _showControls) {
      setState(() => _showControls = false); // scrolling down
    } else if (offset < _lastOffset && !_showControls) {
      setState(() => _showControls = true); // scrolling up
    }
    _lastOffset = offset;
  }

  void _initController(String videoId) {
    final id = YoutubePlayer.convertUrlToId(videoId) ?? videoId;
    _controller =
        YoutubePlayerController(
          initialVideoId: id,
          flags: const YoutubePlayerFlags(autoPlay: true, mute: false),
        )..addListener(() {
          if (mounted) {
            setState(() {
              _isPlaying = _controller.value.isPlaying;
            });
          }
        });
  }

  void _playSongAt(int index) {
    if (index >= 0 && index < widget.songs.length) {
      _currentIndex = index;
      if (!kIsWeb) {
        _controller.load(_currentSong['videoId']);
        _controller.play();
      }
      setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_currentSong['title'])),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: kIsWeb
                  ? Container(
                      color: Colors.black12,
                      child: const Center(
                        child: Text(
                          'YouTube Player not available on Web',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : YoutubePlayer(
                      controller: _controller,
                      showVideoProgressIndicator: true,
                      progressIndicatorColor: theme.colorScheme.primary,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    _currentSong['title'],
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _currentSong['artist'],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 36,
                        onPressed: () => _playSongAt(_currentIndex - 1),
                      ),
                      IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        iconSize: 48,
                        onPressed: () {
                          if (!kIsWeb) {
                            _isPlaying
                                ? _controller.pause()
                                : _controller.play();
                          }
                          setState(() => _isPlaying = !_isPlaying);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 36,
                        onPressed: () => _playSongAt(_currentIndex + 1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (!kIsWeb) {
      _controller.dispose();
    }
    super.dispose();
  }
}
