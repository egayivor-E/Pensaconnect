// widgets/timeline_post_tile.dart
//
// A single grid tile for a timeline post — the compact square thumbnail
// with the like pill (bottom-left) and comment badge (top-right). This
// used to be defined only inline inside profile_screen.dart's own "Posts"
// grid, so another user's profile rendered posts as full vertical cards
// instead (_PostCard, now removed) — a different look from what the
// profile owner sees on their own timeline. Both profile_screen.dart and
// user_profile_screen.dart now build their grid out of this same tile, so
// a post looks identical whether you're viewing your own profile or
// someone else's.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/timeline_post_model.dart';
import 'timeline_post_viewer.dart' show resolveTimelineMediaUrl;

class TimelinePostTile extends StatelessWidget {
  final TimelinePost post;
  final bool isLiked;
  final bool isInFlight;

  /// Number of columns the tile is being rendered in — used only to size
  /// the network image's decode cache (memCacheWidth), matching whichever
  /// grid (own profile or another user's) is hosting the tile.
  final int crossAxisCount;

  final VoidCallback onTap;
  final VoidCallback onLike;

  const TimelinePostTile({
    super.key,
    required this.post,
    required this.isLiked,
    required this.isInFlight,
    required this.crossAxisCount,
    required this.onTap,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final resolvedUrl = resolveTimelineMediaUrl(post.imageUrl);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (post.isVideo)
            resolvedUrl != null
                ? TimelineVideoThumb(url: resolvedUrl)
                : Container(
                    color: Colors.black87,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.videocam_off_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  )
          else if (resolvedUrl != null)
            CachedNetworkImage(
              imageUrl: resolvedUrl,
              fit: BoxFit.cover,
              memCacheWidth:
                  ((width / crossAxisCount) *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
              placeholder: (ctx, url) =>
                  Container(color: theme.colorScheme.surfaceVariant),
              errorWidget: (_, __, ___) => Container(
                color: theme.colorScheme.surfaceVariant,
                child: const Icon(Icons.image_not_supported_outlined),
              ),
            )
          else
            Container(
              color: theme.colorScheme.surfaceVariant,
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              child: Text(
                post.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),

          // Reaction pill — every post can be reacted to (owner or not);
          // delete lives behind the "⋮" menu in the full post viewer
          // instead of an easy-to-mis-tap icon on every tile.
          Positioned(
            left: 6,
            bottom: 6,
            child: GestureDetector(
              onTap: isInFlight ? null : onLike,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.redAccent : Colors.white,
                      size: 14,
                    ),
                    if (post.likeCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${post.likeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Comment-count badge, top-right, so it's clear the tile is
          // tappable for comments too — not just likeable.
          if (post.commentCount > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.mode_comment_outlined,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Muted, paused first-frame preview of a video post's grid tile, with a
/// play badge on top — shared by every screen that renders a posts grid.
class TimelineVideoThumb extends StatefulWidget {
  final String url;

  const TimelineVideoThumb({super.key, required this.url});

  @override
  State<TimelineVideoThumb> createState() => _TimelineVideoThumbState();
}

class _TimelineVideoThumbState extends State<TimelineVideoThumb> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      // Thumbnails just show the first frame — muted and paused, never
      // autoplaying inside a scrolling grid.
      await controller.setVolume(0);
      await controller.seekTo(Duration.zero);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      debugPrint('Timeline video thumbnail failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          if (_ready && _controller != null)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else if (_failed)
            const Icon(
              Icons.videocam_off_outlined,
              color: Colors.white54,
              size: 28,
            )
          else
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.35),
            ),
            padding: const EdgeInsets.all(6),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
