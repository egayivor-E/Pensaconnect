import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService with ChangeNotifier {
  // Singleton instance
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal() {
    _setupAudioListeners();
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentSongId;
  bool _isLoading = false;

  // Getters
  PlayerState get playerState => _playerState;
  Duration get duration => _duration;
  Duration get position => _position;
  String? get currentSongId => _currentSongId;
  bool get isLoading => _isLoading;
  bool get isPlaying => _playerState == PlayerState.playing;

  void _setupAudioListeners() {
    // Duration listener
    _audioPlayer.onDurationChanged.listen((Duration d) {
      _duration = d;
      notifyListeners();
    });

    // Position listener
    _audioPlayer.onPositionChanged.listen((Duration p) {
      _position = p;
      notifyListeners();
    });

    // Player state listener
    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      _playerState = state;
      notifyListeners();
    });

    // Completion listener
    _audioPlayer.onPlayerComplete.listen((_) {
      _playerState = PlayerState.stopped;
      _position = Duration.zero;
      notifyListeners();
    });

    // Error listener
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped) {
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  /// Play audio from URL or local path
  Future<void> playAudio({
    required String songId,
    required String audioSource,
    bool isLocal = false,
  }) async {
    try {
      _isLoading = true;
      _currentSongId = songId;
      notifyListeners();

      if (isLocal) {
        await _audioPlayer.play(UrlSource(audioSource));
      } else {
        await _audioPlayer.play(UrlSource(audioSource));
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _currentSongId = null;
      notifyListeners();
      throw Exception('Failed to play audio: $e');
    }
  }

  /// Pause audio
  Future<void> pauseAudio() async {
    await _audioPlayer.pause();
    notifyListeners();
  }

  /// Resume audio
  Future<void> resumeAudio() async {
    await _audioPlayer.resume();
    notifyListeners();
  }

  /// Stop audio
  Future<void> stopAudio() async {
    await _audioPlayer.stop();
    _position = Duration.zero;
    _currentSongId = null;
    notifyListeners();
  }

  /// Seek to position
  Future<void> seekAudio(Duration position) async {
    await _audioPlayer.seek(position);
    notifyListeners();
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume.clamp(0.0, 1.0));
    notifyListeners();
  }

  /// Set playback rate (0.5 to 2.0)
  Future<void> setPlaybackRate(double rate) async {
    await _audioPlayer.setPlaybackRate(rate.clamp(0.5, 2.0));
    notifyListeners();
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (_playerState == PlayerState.playing) {
      await pauseAudio();
    } else {
      await resumeAudio();
    }
  }

  /// Get formatted position string
  String get formattedPosition {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = twoDigits(_position.inHours);
    final minutes = twoDigits(_position.inMinutes.remainder(60));
    final seconds = twoDigits(_position.inSeconds.remainder(60));

    return hours == "00" ? "$minutes:$seconds" : "$hours:$minutes:$seconds";
  }

  /// Get formatted duration string
  String get formattedDuration {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = twoDigits(_duration.inHours);
    final minutes = twoDigits(_duration.inMinutes.remainder(60));
    final seconds = twoDigits(_duration.inSeconds.remainder(60));

    return hours == "00" ? "$minutes:$seconds" : "$hours:$minutes:$seconds";
  }

  /// Get progress percentage (0.0 to 1.0)
  double get progress {
    if (_duration.inSeconds == 0) return 0.0;
    return _position.inSeconds / _duration.inSeconds;
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
