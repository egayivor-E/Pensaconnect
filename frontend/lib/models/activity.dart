import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:timeago/timeago.dart' as timeago;

class Activity {
  // ✅ The activity log row's own id (distinct from targetId, which is
  // the id of whatever the activity is *about*). Required for dedup —
  // without a stable key, re-fetching (pull-to-refresh, rebuilds) has
  // no way to tell "already have this one" from "new entry" and the
  // list silently grows duplicates.
  final int id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final DateTime createdAt;
  // ✅ Optional author identity. Nullable because older/unmigrated backend
  // rows or activity types without a clear actor (e.g. system messages)
  // may not have one — UI falls back to the icon-in-circle treatment
  // when these are null rather than crashing or showing a broken image.
  final String? authorName;
  final String? authorAvatarUrl;
  final int? authorId;
  // ✅ What this activity is "about" — e.g. targetType "testimony" +
  // targetId 42 points at Testimony#42. Nullable because not every
  // activity has (or needs) a real backing object. Lets the feed deep
  // link into the actual content and reuse its existing like/comment
  // endpoints instead of treating the activity log itself as likeable.
  final String? targetType;
  final int? targetId;
  // ✅ Whether the requesting user has already liked/prayed for this
  // activity's target, as reported by the backend. Used to hydrate the
  // feed's liked state on load rather than assuming everything starts
  // unliked every session. Defaults to false for older/cached payloads
  // that predate this field.
  final bool hasLiked;
  // ✅ Optional media thumbnail (e.g. the first image attached to a
  // forum post). Nullable — most activity types have no image and the
  // feed card falls back to the icon-in-circle treatment.
  final String? imageUrl;
  // ✅ When present, this activity gets a "reel" — an autoplaying,
  // muted-by-default video card instead of a static image. If both
  // imageUrl and videoUrl are set, the video takes priority.
  final String? videoUrl;
  // ✅ Like/comment counts for whatever this activity points at (only
  // populated for target types the backend batches counts for today —
  // "post"). Null means "not provided", not "zero", so the UI can
  // choose to hide the count entirely rather than show a false 0.
  final int? likeCount;
  final int? commentCount;
  // ✅ For target_type == "post": the forum thread the post lives in,
  // so the feed can deep link straight to it.
  final int? threadId;
  Activity({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.createdAt,
    this.authorName,
    this.authorAvatarUrl,
    this.authorId,
    this.targetType,
    this.targetId,
    this.hasLiked = false,
    this.imageUrl,
    this.videoUrl,
    this.likeCount,
    this.commentCount,
    this.threadId,
  });

  /// Only exposes the fields the feed actually needs to update in place
  /// after a local action (currently: optimistic like toggling). Not a
  /// general-purpose copyWith — deliberately narrow so it can't silently
  /// drop a field a future caller forgets to pass through.
  Activity copyWith({bool? hasLiked, int? likeCount}) {
    return Activity(
      id: id,
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      createdAt: createdAt,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      authorId: authorId,
      targetType: targetType,
      targetId: targetId,
      hasLiked: hasLiked ?? this.hasLiked,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount,
      threadId: threadId,
    );
  }

  /// Returns a "5m ago" style string
  String get timeAgo => timeago.format(createdAt);
  bool get hasAuthorAvatar =>
      authorAvatarUrl != null && authorAvatarUrl!.isNotEmpty;
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  factory Activity.fromJson(Map<String, dynamic> json) {
    // Matches Activity.to_dict(include_user=True) on the backend:
    // { ..., "user": { "id", "username", "fullName", "profilePicture" } }
    // Falls back gracefully if "user" is absent (e.g. older cached data).
    final Map<String, dynamic>? author = json['user'] as Map<String, dynamic>?;
    return Activity(
      // Falls back to a hash of title+createdAt if the backend ever omits
      // "id" (shouldn't happen, but keeps fromJson from crashing / keeps
      // dedup-by-id from silently colliding every unidentified row onto 0).
      id:
          (json['id'] as num?)?.toInt() ??
          Object.hash(json['title'], json['created_at'] ?? json['createdAt']),
      title: json['title'] ?? 'Untitled',
      subtitle: json['subtitle'] ?? '',
      icon: _mapIcon(json['icon']),
      color: _mapColor(json['color']),
      createdAt:
          DateTime.tryParse(
            json['created_at']?.toString() ??
                json['createdAt']?.toString() ??
                '',
          ) ??
          DateTime.now(),
      authorName:
          author?['fullName'] as String? ?? author?['username'] as String?,
      authorAvatarUrl: author?['profilePicture'] as String?,
      authorId: (author?['id'] as num?)?.toInt(),
      targetType: json['targetType'] as String?,
      targetId: (json['targetId'] as num?)?.toInt(),
      hasLiked: json['hasLiked'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String?,
      videoUrl: json['videoUrl'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt(),
      commentCount: (json['commentCount'] as num?)?.toInt(),
      threadId: (json['threadId'] as num?)?.toInt(),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'icon': icon.codePoint,
      'color': color.value,
      'created_at': createdAt.toIso8601String(),
      if (targetType != null) 'targetType': targetType,
      if (targetId != null) 'targetId': targetId,
      'hasLiked': hasLiked,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (likeCount != null) 'likeCount': likeCount,
      if (commentCount != null) 'commentCount': commentCount,
      if (threadId != null) 'threadId': threadId,
      if (authorName != null)
        'user': {
          if (authorId != null) 'id': authorId,
          'fullName': authorName,
          if (authorAvatarUrl != null) 'profilePicture': authorAvatarUrl,
        },
    };
  }

  /// Maps string from API to Flutter IconData
  static IconData _mapIcon(String? iconName) {
    switch (iconName) {
      case 'groups':
        return Icons.groups;
      case 'event':
        return Icons.event;
      case 'book':
        return FontAwesome.book;
      case 'forum':
        return Icons.forum;
      case 'pray':
        return Icons.self_improvement;
      case 'article':
        return Icons.article;
      default:
        return Icons.notifications;
    }
  }

  /// Maps string from API to Flutter Color
  static Color _mapColor(String? colorName) {
    switch (colorName) {
      case 'teal':
        return Colors.teal;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'red':
        return Colors.red;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
