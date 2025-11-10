import 'package:flutter/foundation.dart';
import '../repositories/forum_repository.dart';

class ThreadsProvider extends ChangeNotifier {
  final ForumRepository _repo = ForumRepository();

  List<Map<String, dynamic>> _threads = [];
  bool _loading = false;

  List<Map<String, dynamic>> get threads => _threads;
  bool get isLoading => _loading;

  ThreadsProvider() {
    fetchThreads();
  }

  // ---------------- FETCH THREADS ----------------
  Future<void> fetchThreads() async {
    _loading = true;
    notifyListeners();

    try {
      _threads = await _repo.getThreads();
    } catch (e) {
      if (kDebugMode) print("⚠️ Error fetching threads: $e");
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---------------- ADD THREAD ----------------
  Future<void> addThread(String title, String description) async {
    try {
      final success = await _repo.createThread(title, description);
      if (success) await fetchThreads();
    } catch (e) {
      if (kDebugMode) print("⚠️ Error adding thread: $e");
    }
  }

  // ---------------- LIKE THREAD ----------------
  Future<void> toggleLike(int threadId) async {
    try {
      final index = _threads.indexWhere((t) => t['id'] == threadId);
      if (index == -1) return;

      final thread = _threads[index];
      final bool liked = thread['liked_by_me'] ?? false;
      final bool disliked = thread['disliked_by_me'] ?? false;

      // ✅ Optimistic update
      if (liked) {
        thread['like_count'] = (thread['like_count'] ?? 1) - 1;
      } else {
        thread['like_count'] = (thread['like_count'] ?? 0) + 1;
        if (disliked && (thread['dislike_count'] ?? 0) > 0) {
          thread['dislike_count'] = (thread['dislike_count'] ?? 1) - 1;
          thread['disliked_by_me'] = false;
        }
      }
      thread['liked_by_me'] = !liked;
      notifyListeners();

      // ✅ API call (JSON-safe version)
      await _repo.toggleReaction(threadId, "like");

      // Optional: Re-fetch to stay perfectly in sync
      await fetchThreads();
    } catch (e) {
      if (kDebugMode) print("⚠️ Error toggling like: $e");
    }
  }

  // ---------------- DISLIKE THREAD ----------------
  Future<void> toggleDislike(int threadId) async {
    try {
      final index = _threads.indexWhere((t) => t['id'] == threadId);
      if (index == -1) return;

      final thread = _threads[index];
      final bool disliked = thread['disliked_by_me'] ?? false;
      final bool liked = thread['liked_by_me'] ?? false;

      // ✅ Optimistic update
      if (disliked) {
        thread['dislike_count'] = (thread['dislike_count'] ?? 1) - 1;
      } else {
        thread['dislike_count'] = (thread['dislike_count'] ?? 0) + 1;
        if (liked && (thread['like_count'] ?? 0) > 0) {
          thread['like_count'] = (thread['like_count'] ?? 1) - 1;
          thread['liked_by_me'] = false;
        }
      }
      thread['disliked_by_me'] = !disliked;
      notifyListeners();

      // ✅ API call
      await _repo.toggleReaction(threadId, "dislike");

      // Optional sync refresh
      await fetchThreads();
    } catch (e) {
      if (kDebugMode) print("⚠️ Error toggling dislike: $e");
    }
  }
}
