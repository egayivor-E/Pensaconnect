import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pensaconnect/models/bible_models.dart';
import 'package:pensaconnect/services/api_service.dart';

typedef FromJson<T> = T Function(Map<String, dynamic>);

class BibleRepository {
  const BibleRepository._();

  /// ---- Helpers -------------------------------------------------------------

  static Map<String, dynamic> _decodeToMap(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Unexpected response type: expected Map, got ${decoded.runtimeType}',
      );
    }
    return decoded;
  }

  /// Unwraps `{ status, message, data }` and supports both:
  /// - data: [ ... ]
  /// - data: { items: [ ... ], total, page, pages }
  static List<dynamic> _extractListPayload(Map<String, dynamic> root) {
    final data = root['data'];
    if (data == null) return const [];

    if (data is List) return data;

    if (data is Map<String, dynamic>) {
      for (final key in const ['items', 'results', 'data', 'list']) {
        final v = data[key];
        if (v is List) return v;
      }
    }

    throw FormatException('Response "data" did not contain a list.');
  }

  /// Extracts a single object `{ status, message, data: {...} }`
  static T _extractObjectPayload<T>(
    Map<String, dynamic> root,
    FromJson<T> fromJson,
  ) {
    final data = root['data'];
    if (data is Map<String, dynamic>) {
      return fromJson(data);
    }
    throw FormatException('Response "data" did not contain an object.');
  }

  static Exception _httpError(http.Response response) {
    try {
      final map = _decodeToMap(response);
      final message = map['message']?.toString();
      return Exception(
        'HTTP ${response.statusCode}${message != null ? ": $message" : ""}',
      );
    } catch (_) {
      return Exception('HTTP ${response.statusCode}');
    }
  }

  /// Generic parser for list endpoints
  static List<T> _parseList<T>(http.Response response, FromJson<T> fromJson) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
    final map = _decodeToMap(response);
    final list = _extractListPayload(map);
    return list
        .map((e) => fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Generic parser for object endpoints
  static T _parseObject<T>(http.Response response, FromJson<T> fromJson) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
    final map = _decodeToMap(response);
    return _extractObjectPayload(map, fromJson);
  }

  // ---------------------------------------------------------------------------
  // DEVOTIONS
  // ---------------------------------------------------------------------------

  static Future<List<Devotion>> fetchDevotions() async {
    final response = await ApiService.get("bible/devotions");
    return _parseList<Devotion>(response, (m) => Devotion.fromJson(m));
  }

  static Future<Devotion> fetchDevotion(int id) async {
    final response = await ApiService.get("bible/devotions/$id");
    return _parseObject<Devotion>(response, (m) => Devotion.fromJson(m));
  }

  static Future<Devotion> createDevotion(Map<String, dynamic> payload) async {
    final response = await ApiService.post("bible/devotions", payload);
    return _parseObject<Devotion>(response, (m) => Devotion.fromJson(m));
  }

  static Future<Devotion> updateDevotion(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final response = await ApiService.patch("bible/devotions/$id", payload);
    return _parseObject<Devotion>(response, (m) => Devotion.fromJson(m));
  }

  static Future<void> deleteDevotion(int id) async {
    final response = await ApiService.delete("bible/devotions/$id");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  // ---------------------------------------------------------------------------
  // STUDY PLANS
  // ---------------------------------------------------------------------------
  static Future<List<StudyPlan>> fetchPlans() async {
    final response = await ApiService.get("bible/plans");
    return _parseList<StudyPlan>(response, (m) => StudyPlan.fromJson(m));
  }

  static Future<StudyPlan> fetchPlan(int id) async {
    final response = await ApiService.get("bible/plans/$id");
    return _parseObject<StudyPlan>(response, (m) => StudyPlan.fromJson(m));
  }

  static Future<StudyPlan> createPlan(Map<String, dynamic> payload) async {
    final response = await ApiService.post("bible/plans", payload);
    return _parseObject<StudyPlan>(response, (m) => StudyPlan.fromJson(m));
  }

  /// UPDATE THIS METHOD to use the real API
  static Future<void> createStudyPlan(StudyPlan plan) async {
    try {
      // Convert StudyPlan to backend-compatible payload
      final payload = {
        'title': plan.title,
        'description': plan.description ?? '',
        'level': _convertDifficultyToLevel(
          plan.difficulty,
        ), // difficulty -> level
        'total_days': plan.dayCount ?? 7, // dayCount -> total_days
        'verses': plan.verses,
        'is_public': false,
      };

      // Use the existing createPlan method that calls the real API
      final createdPlan = await createPlan(payload);

      debugPrint('✅ Study plan created successfully: ${createdPlan.title}');
      debugPrint('   - ID: ${createdPlan.id}');
      debugPrint('   - Verses: ${plan.verses.length}');
      debugPrint('   - Days: ${plan.dayCount}');
      debugPrint('   - Difficulty: ${plan.difficulty}');
    } catch (e) {
      debugPrint('❌ Error creating study plan: $e');
      throw Exception('Failed to create study plan: $e');
    }
  }

  /// Helper method to convert StudyPlanDifficulty to backend level
  static String _convertDifficultyToLevel(StudyPlanDifficulty? difficulty) {
    switch (difficulty) {
      case StudyPlanDifficulty.beginner:
        return 'BEGINNER';
      case StudyPlanDifficulty.intermediate:
        return 'INTERMEDIATE';
      case StudyPlanDifficulty.advanced:
        return 'ADVANCED';
      default:
        return 'BEGINNER';
    }
  }

  static Future<StudyPlan> updatePlan(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final response = await ApiService.patch("bible/plans/$id", payload);
    return _parseObject<StudyPlan>(response, (m) => StudyPlan.fromJson(m));
  }

  static Future<void> deletePlan(int id) async {
    final response = await ApiService.delete("bible/plans/$id");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  // Study Plan Days
  static Future<List<StudyPlanDay>> fetchPlanDays(int planId) async {
    final response = await ApiService.get("bible/plans/$planId/days");
    return _parseList<StudyPlanDay>(response, (m) => StudyPlanDay.fromJson(m));
  }

  static Future<StudyPlanDay> updatePlanDay(
    int planId,
    int dayNumber,
    Map<String, dynamic> payload,
  ) async {
    final response = await ApiService.patch(
      "bible/plans/$planId/days/$dayNumber",
      payload,
    );
    return _parseObject<StudyPlanDay>(
      response,
      (m) => StudyPlanDay.fromJson(m),
    );
  }

  static Future<StudyPlan?> getActivePlan() async {
    try {
      final plans = await fetchPlans();
      for (final plan in plans) {
        try {
          final progress = await getProgress(plan.id, 'study_plan');
          // If progress exists and not completed, consider this active
          if (progress != null &&
              (progress.isCompleted == false &&
                  (progress.progress ?? 0.0) < 1.0)) {
            return plan;
          }
        } catch (_) {
          // ignore missing progress for this plan and continue searching
        }
      }

      // Optionally: treat plans with no progress but with some other business logic as active.
      // For now we'll return null if no in-progress plan is found.
      return null;
    } catch (e) {
      // Don't crash the UI when fetching fails — surface as null so caller can continue.
      debugPrint('Error in getActivePlan: $e');
      return null;
    }
  }

  static Future<void> markPlanDayComplete(int planId, int dayNumber) async {
    final response = await ApiService.post(
      "bible/plans/$planId/days/$dayNumber/complete",
      {},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  // ---------------------------------------------------------------------------
  // ARCHIVES
  // ---------------------------------------------------------------------------

  static Future<List<ArchiveItem>> fetchArchive() async {
    final response = await ApiService.get("bible/archives");
    return _parseList<ArchiveItem>(response, (m) => ArchiveItem.fromJson(m));
  }

  static Future<ArchiveItem> fetchArchiveItem(int id) async {
    final response = await ApiService.get("bible/archives/$id");
    return _parseObject<ArchiveItem>(response, (m) => ArchiveItem.fromJson(m));
  }

  static Future<ArchiveItem> createArchive(Map<String, dynamic> payload) async {
    final response = await ApiService.post("bible/archives", payload);
    return _parseObject<ArchiveItem>(response, (m) => ArchiveItem.fromJson(m));
  }

  static Future<ArchiveItem> updateArchive(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final response = await ApiService.patch("bible/archives/$id", payload);
    return _parseObject<ArchiveItem>(response, (m) => ArchiveItem.fromJson(m));
  }

  static Future<void> deleteArchive(int id) async {
    final response = await ApiService.delete("bible/archives/$id");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  // ---------------------------------------------------------------------------
  // READING PROGRESS & STATISTICS
  // ---------------------------------------------------------------------------

  // Progress Tracking
  static Future<ReadingProgress> saveProgress(ReadingProgress progress) async {
    final response = await ApiService.post("bible/progress", progress.toJson());
    return _parseObject<ReadingProgress>(
      response,
      (m) => ReadingProgress.fromJson(m),
    );
  }

  static Future<ReadingProgress?> getProgress(
    int itemId,
    String itemType,
  ) async {
    try {
      final response = await ApiService.get("bible/progress/$itemType/$itemId");
      return _parseObject<ReadingProgress>(
        response,
        (m) => ReadingProgress.fromJson(m),
      );
    } catch (e) {
      // Return null if progress doesn't exist (404)
      if (e.toString().contains('404')) {
        return null;
      }
      rethrow;
    }
  }

  static Future<List<ReadingProgress>> getProgressForType(
    String itemType,
  ) async {
    final response = await ApiService.get("bible/progress/$itemType");
    return _parseList<ReadingProgress>(
      response,
      (m) => ReadingProgress.fromJson(m),
    );
  }

  static Future<void> markAsCompleted(int itemId, String itemType) async {
    final response = await ApiService.post(
      "bible/progress/$itemType/$itemId/complete",
      {},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  static Future<void> updateProgress(
    int itemId,
    String itemType,
    double progress,
    int currentPage,
  ) async {
    final response =
        await ApiService.patch("bible/progress/$itemType/$itemId", {
          'progress': progress,
          'currentPage': currentPage,
          'lastRead': DateTime.now().toIso8601String(),
        });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  static Future<void> resetProgress(int itemId, String itemType) async {
    final response = await ApiService.delete(
      "bible/progress/$itemType/$itemId",
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  // Add to BibleRepository archive
  static Future<ArchiveItem> archiveDevotion(int devotionId) async {
    final response = await ApiService.post(
      "bible/devotions/$devotionId/archive",
      {},
    );
    return _parseObject<ArchiveItem>(response, (m) => ArchiveItem.fromJson(m));
  }

  static Future<ArchiveItem> archiveStudyPlan(int planId) async {
    final response = await ApiService.post("bible/plans/$planId/archive", {});
    return _parseObject<ArchiveItem>(response, (m) => ArchiveItem.fromJson(m));
  }

  static Future<void> unarchiveItem(int archiveId) async {
    final response = await ApiService.delete("bible/archives/$archiveId");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  // Reading Statistics
  static Future<UserReadingStats> getUserReadingStats() async {
    final response = await ApiService.get("bible/stats");
    return _parseObject<UserReadingStats>(
      response,
      (m) => UserReadingStats.fromJson(m),
    );
  }

  static Future<Map<String, dynamic>> getReadingInsights() async {
    final response = await ApiService.get("bible/insights");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
    final map = _decodeToMap(response);
    return map['data'] as Map<String, dynamic>? ?? {};
  }

  // Recent Activity
  static Future<List<ReadingProgress>> getRecentActivity({
    int limit = 10,
  }) async {
    final response = await ApiService.get("bible/activity?limit=$limit");
    return _parseList<ReadingProgress>(
      response,
      (m) => ReadingProgress.fromJson(m),
    );
  }

  // Reading Streaks
  static Future<Map<String, dynamic>> getReadingStreak() async {
    final response = await ApiService.get("bible/streak");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
    final map = _decodeToMap(response);
    return map['data'] as Map<String, dynamic>? ?? {};
  }

  // Completion Tracking
  static Future<Map<String, dynamic>> getCompletionStats() async {
    final response = await ApiService.get("bible/completion");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
    final map = _decodeToMap(response);
    return map['data'] as Map<String, dynamic>? ?? {};
  }

  // Bulk Progress Operations
  static Future<void> syncLocalProgress(
    List<ReadingProgress> progressList,
  ) async {
    final response = await ApiService.post("bible/progress/sync", {
      'progress': progressList.map((p) => p.toJson()).toList(),
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  // Search with Progress
  static Future<List<Devotion>> searchDevotionsWithProgress(
    String query,
  ) async {
    final response = await ApiService.get(
      "bible/devotions/search?q=${Uri.encodeQueryComponent(query)}",
    );
    return _parseList<Devotion>(response, (m) => Devotion.fromJson(m));
  }

  static Future<List<StudyPlan>> searchPlansWithProgress(String query) async {
    final response = await ApiService.get(
      "bible/plans/search?q=${Uri.encodeQueryComponent(query)}",
    );
    return _parseList<StudyPlan>(response, (m) => StudyPlan.fromJson(m));
  }

  // Favorites & Bookmarks
  static Future<List<Devotion>> getFavoriteDevotions() async {
    final response = await ApiService.get("bible/devotions/favorites");
    return _parseList<Devotion>(response, (m) => Devotion.fromJson(m));
  }

  static Future<void> toggleFavoriteDevotion(int devotionId) async {
    final response = await ApiService.post(
      "bible/devotions/$devotionId/favorite",
      {},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
  }

  // Recommendations based on progress
  static Future<List<dynamic>> getRecommendedContent() async {
    final response = await ApiService.get("bible/recommendations");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
    final map = _decodeToMap(response);
    final data = map['data'] as Map<String, dynamic>? ?? {};

    final recommendations = <dynamic>[];

    // Parse devotions
    if (data['devotions'] is List) {
      recommendations.addAll(
        (data['devotions'] as List).map((e) => Devotion.fromJson(e)),
      );
    }

    // Parse study plans
    if (data['plans'] is List) {
      recommendations.addAll(
        (data['plans'] as List).map((e) => StudyPlan.fromJson(e)),
      );
    }

    return recommendations;
  }

  // Export Progress Data
  static Future<String> exportProgressData() async {
    final response = await ApiService.get("bible/progress/export");
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(response);
    }
    final map = _decodeToMap(response);
    return map['data']?['exportUrl'] as String? ?? '';
  }
}
