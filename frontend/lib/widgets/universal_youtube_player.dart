import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/worship_song.dart';

class UniversalYoutubePlayer extends StatefulWidget {
  final WorshipSong song;
  final bool autoPlay;
  final double aspectRatio;
  final bool showControls;
  final bool mute;

  const UniversalYoutubePlayer({
    super.key,
    required this.song,
    this.autoPlay = false,
    this.aspectRatio = 16 / 9,
    this.showControls = true,
    this.mute = false,
  });

  @override
  State<UniversalYoutubePlayer> createState() => _UniversalYoutubePlayerState();
}

class _UniversalYoutubePlayerState extends State<UniversalYoutubePlayer> {
  YoutubePlayerController? _youtubeController;
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _thumbnailError = false;
  String? _errorMessage; // NEW: Track specific error messages

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    print('🔄 Initializing player for song: ${widget.song.title}');
    print('🎵 Media type: ${widget.song.mediaType}');
    print('🎵 Video ID: ${widget.song.videoId}');
    print('🎵 Audio URL: ${widget.song.audioUrl}');
    print('🎵 Video URL: ${widget.song.videoUrl}');

    try {
      if (widget.song.isYouTube) {
        // ✅ FIX: Check if videoId exists before initializing YouTube
        if (widget.song.videoId == null || widget.song.videoId!.isEmpty) {
          throw Exception('YouTube video ID is missing');
        }

        print('🎬 Initializing YouTube player with ID: ${widget.song.videoId}');
        _youtubeController = YoutubePlayerController.fromVideoId(
          videoId: widget.song.videoId!,
          autoPlay: widget.autoPlay,
          params: YoutubePlayerParams(
            mute: widget.mute,
            showControls: widget.showControls,
            showFullscreenButton: true,
            enableCaption: true,
            strictRelatedVideos: false,
            enableJavaScript: true,
            playsInline: false,
            loop: false,
          ),
        );
        _isLoading = false;
      } else if (widget.song.isAudio) {
        // ✅ FIX: Check if audioUrl exists
        if (widget.song.audioUrl == null || widget.song.audioUrl!.isEmpty) {
          throw Exception('Audio URL is missing');
        }
        _initializeAudioPlayer();
      } else if (widget.song.isVideo) {
        // ✅ FIX: Check if videoUrl exists
        if (widget.song.videoUrl == null || widget.song.videoUrl!.isEmpty) {
          throw Exception('Video URL is missing');
        }
        _initializeVideoPlayer();
      } else {
        throw Exception('Unknown media type: ${widget.song.mediaType}');
      }
    } catch (e) {
      print('❌ Error initializing player: $e');
      _handleError('Failed to initialize media player: $e');
    }
  }

  void _initializeAudioPlayer() async {
    try {
      _audioPlayer = AudioPlayer();
      final source = UrlSource(widget.song.audioUrl!);

      await _audioPlayer!.setSource(source);

      // Listen to audio events
      _audioPlayer!.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() => _isPlaying = false);
        }
      });

      _audioPlayer!.onDurationChanged.listen((duration) {
        if (mounted) {
          setState(() => _duration = duration);
        }
      });

      _audioPlayer!.onPositionChanged.listen((position) {
        if (mounted) {
          setState(() => _position = position);
        }
      });

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (widget.autoPlay) {
            _audioPlayer!.resume();
            _isPlaying = true;
          }
        });
      }
    } catch (e) {
      _handleError('Failed to load audio: $e');
    }
  }

  void _initializeVideoPlayer() async {
    try {
      _videoController = VideoPlayerController.network(widget.song.videoUrl!)
        ..initialize()
            .then((_) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  if (widget.autoPlay) {
                    _videoController!.play();
                    _isPlaying = true;
                  }
                });
              }
            })
            .catchError((e) {
              _handleError('Failed to load video: $e');
            });

      _videoController!.addListener(() {
        if (mounted && _videoController!.value.isInitialized) {
          setState(() {
            _isPlaying = _videoController!.value.isPlaying;
          });
        }
      });
    } catch (e) {
      _handleError('Failed to initialize video player: $e');
    }
  }

  // ✅ NEW: Centralized error handling
  void _handleError(String message) {
    print('❌ Player Error: $message');
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
    }
  }

  void _togglePlayPause() {
    try {
      if (widget.song.isAudio && _audioPlayer != null) {
        if (_isPlaying) {
          _audioPlayer!.pause();
        } else {
          _audioPlayer!.resume();
        }
        setState(() => _isPlaying = !_isPlaying);
      } else if (widget.song.isVideo &&
          _videoController != null &&
          _videoController!.value.isInitialized) {
        setState(() {
          _isPlaying ? _videoController!.pause() : _videoController!.play();
          _isPlaying = !_isPlaying;
        });
      }
    } catch (e) {
      _handleError('Playback error: $e');
    }
  }

  void _seekAudio(Duration position) {
    if (widget.song.isAudio && _audioPlayer != null) {
      _audioPlayer!.seek(position);
    }
  }

  @override
  void didUpdateWidget(UniversalYoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.song.id != widget.song.id) {
      print('🔄 Song changed, reinitializing player');
      setState(() {
        _isLoading = true;
        _isPlaying = false;
        _duration = Duration.zero;
        _position = Duration.zero;
        _thumbnailError = false;
        _errorMessage = null; // Reset error
      });

      _youtubeController?.close();
      _videoController?.dispose();
      _audioPlayer?.dispose();

      _initializeController();
    }
  }

  @override
  void dispose() {
    print('♻️ Disposing player');
    _youtubeController?.close();
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ FIX: Safe aspect ratio calculation
    final aspectRatio = widget.song.isAudio ? 1.0 : widget.aspectRatio;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        children: [
          // ✅ FIX: YouTube Player with null safety
          if (widget.song.isYouTube &&
              _youtubeController != null &&
              !_isLoading)
            YoutubePlayerScaffold(
              controller: _youtubeController!,
              builder: (context, player) => player,
            ),

          // ✅ FIX: Video Player with null safety and error handling
          if (widget.song.isVideo && _videoController != null && !_isLoading)
            _videoController!.value.isInitialized
                ? VideoPlayer(_videoController!)
                : _buildErrorWidget('Video not available'),

          // ✅ FIX: Audio Player UI with null safety
          if (widget.song.isAudio && _audioPlayer != null && !_isLoading)
            _buildAudioPlayerUI(),

          // ✅ FIX: Loading indicator
          if (_isLoading)
            Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Loading media...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          // ✅ FIX: Error state
          if (_errorMessage != null && !_isLoading)
            _buildErrorWidget(_errorMessage!),

          // ✅ FIX: Custom play/pause overlay with better null safety
          if (!_isLoading &&
              ((widget.song.isVideo &&
                      _videoController?.value.isInitialized == true) ||
                  (widget.song.isAudio && _audioPlayer != null)) &&
              _errorMessage == null)
            Positioned.fill(
              child: InkWell(
                onTap: _togglePlayPause,
                child: AnimatedOpacity(
                  opacity: _isPlaying ? 0 : 0.7,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ✅ FIX: Video controls overlay with null safety
          if (widget.song.isVideo &&
              _videoController != null &&
              _videoController!.value.isInitialized &&
              !_isLoading &&
              _errorMessage == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        _videoController!,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.red,
                          bufferedColor: Colors.grey,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                    Text(
                      '${_formatDuration(_videoController!.value.position)} / ${_formatDuration(_videoController!.value.duration)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ✅ NEW: Build error widget
  Widget _buildErrorWidget(String message) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              'Media Error',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                message,
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ FIX: Audio player UI with better organization
  Widget _buildAudioPlayerUI() {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildThumbnailWidget(),
          const SizedBox(height: 20),
          Text(
            widget.song.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            widget.song.artist,
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _buildAudioControls(),
        ],
      ),
    );
  }

  // ✅ FIX: Audio controls with null safety
  Widget _buildAudioControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70),
              ),
              Expanded(
                child: Slider(
                  value: _position.inSeconds.toDouble(),
                  min: 0,
                  max: _duration.inSeconds.toDouble(),
                  onChanged: (value) {
                    _seekAudio(Duration(seconds: value.toInt()));
                  },
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                onPressed: () {}, // Add previous song functionality
              ),
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
                onPressed: _togglePlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white),
                onPressed: () {}, // Add next song functionality
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Thumbnail widget (unchanged from your version)
  Widget _buildThumbnailWidget() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[800],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _thumbnailError
            ? const Center(
                child: Icon(Icons.music_note, size: 60, color: Colors.white54),
              )
            : Image.network(
                widget.song.thumbnailUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _thumbnailError = true;
                      });
                    }
                  });
                  return const Center(
                    child: Icon(
                      Icons.music_note,
                      size: 60,
                      color: Colors.white54,
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}
