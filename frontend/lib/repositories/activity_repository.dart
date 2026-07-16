import 'dart:convert';

import '../models/activity.dart';
import '../services/api_service.dart';

/// One page of the home feed, plus enough info to ask for the next one.
/// [hasMore] / [nextCursor] come straight from the backend's `meta` block
/// — the repository doesn't guess whether more activity exists, it just
/// reports what the server said.
class ActivityFeedPage {
  final List<Activity> activities;
  final bool hasMore;
  final int? nextCursor;

  const ActivityFeedPage({
    required this.activities,
    required this.hasMore,
    required this.nextCursor,
  });
}

class ActivityRepository {
  /// Fetch a page of recent activities from the API.
  ///
  /// Pass [beforeId] (the previous page's [ActivityFeedPage.nextCursor])
  /// to load the page *older* than that activity — e.g. when the user
  /// scrolls to the bottom of the feed. Omit it for the newest page
  /// (initial load / pull-to-refresh).
  Future<ActivityFeedPage> fetchRecentActivities({
    int limit = 20,
    int? beforeId,
  }) async {
    // ✅ No longer swallows failures into an empty list. ApiService.get
    // already throws ApiException on a non-2xx response (see
    // ApiService._handleResponse), which made the old `else` branch here
    // dead code — the real failure path was the catch-all below quietly
    // returning [], which is indistinguishable from "no activity yet".
    // Letting this propagate lets HomeScreen show a real "couldn't load"
    // state with a retry button instead of a misleading empty feed.
    final response = await ApiService.get(
      "activities/recent",
      queryParams: {
        "limit": limit,
        if (beforeId != null) "before_id": beforeId,
      },
      headers: {},
    );

    final Map<String, dynamic> decoded = json.decode(response.body);
    final List<dynamic> data = decoded["data"] ?? [];
    // `meta` is a newer, additive field — defaults keep this working even
    // against an older backend that hasn't deployed it yet, just without
    // real "load more" (has_more defaults to false rather than looping).
    final Map<String, dynamic> meta = decoded["meta"] ?? {};

    final activities = data
        .map<Activity>(
          (jsonItem) => Activity.fromJson(jsonItem as Map<String, dynamic>),
        )
        .toList();

    return ActivityFeedPage(
      activities: activities,
      hasMore: meta["has_more"] ?? false,
      nextCursor: meta["next_cursor"] as int?,
    );
  }
}
