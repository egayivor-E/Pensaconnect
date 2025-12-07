import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class WorshipVideoPlayer extends StatefulWidget {
  final String videoId;
  const WorshipVideoPlayer({super.key, required this.videoId});

  @override
  State<WorshipVideoPlayer> createState() => _WorshipVideoPlayerState();
}

class _WorshipVideoPlayerState extends State<WorshipVideoPlayer> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        enableCaption: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerScaffold(
      controller: _controller,
      builder: (context, player) {
        return AspectRatio(aspectRatio: 16 / 9, child: player);
      },
    );
  }
}
