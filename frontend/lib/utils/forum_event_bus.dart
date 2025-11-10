// utils/forum_event_bus.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/forum_model.dart';

class ForumEventBus {
  static final ForumEventBus _instance = ForumEventBus._internal();
  factory ForumEventBus() => _instance;
  ForumEventBus._internal();

  // ✅ Broadcast controllers for both post and comment events
  final _postController = StreamController<PostEvent>.broadcast();
  final _commentController = StreamController<CommentEvent>.broadcast();

  // ✅ Expose read-only streams
  Stream<PostEvent> get postEvents => _postController.stream;
  Stream<CommentEvent> get commentEvents => _commentController.stream;

  // ✅ Notify when a post is created
  void notifyPostCreated(int threadId, ForumPost post) {
    if (!_postController.isClosed) {
      _postController.add(PostCreatedEvent(threadId, post));
      debugPrint('📢 PostCreatedEvent fired for thread $threadId');
    }
  }

  // ✅ Notify when a post is deleted
  void notifyPostDeleted(int postId) {
    if (!_postController.isClosed) {
      _postController.add(PostDeletedEvent(postId));
      debugPrint('🗑️ PostDeletedEvent fired for post $postId');
    }
  }

  // ✅ Notify when a comment is created
  void notifyCommentCreated(int threadId, int postId, ForumComment comment) {
    if (!_commentController.isClosed) {
      _commentController.add(CommentCreatedEvent(threadId, postId, comment));
      debugPrint(
        '💬 CommentCreatedEvent fired for thread $threadId → post $postId',
      );
    }
  }

  void dispose() {
    _postController.close();
    _commentController.close();
  }
}

//
// ----------------------
//   Event Base Classes
// ----------------------

abstract class PostEvent {}

/// 🔹 Fired when a post is created
class PostCreatedEvent extends PostEvent {
  final int threadId;
  final ForumPost post;
  PostCreatedEvent(this.threadId, this.post);
}

/// 🔹 Fired when a post is deleted
class PostDeletedEvent extends PostEvent {
  final int postId;
  PostDeletedEvent(this.postId);
}

abstract class CommentEvent {}

/// 🔹 Fired when a comment is created
class CommentCreatedEvent extends CommentEvent {
  final int threadId;
  final int postId;
  final ForumComment comment;

  CommentCreatedEvent(this.threadId, this.postId, this.comment);
}
