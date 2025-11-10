import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/prayer_request.dart';
import '../services/api_service.dart';

class PrayerRepository extends ChangeNotifier {
  final List<PrayerRequest> _requests = [];
  bool _isLoading = false;
  bool _hasMore = true;

  int? _currentUserId;
  int get currentUserId => _currentUserId ?? 0; // fallback 0 if not set

  List<PrayerRequest> get requests => _requests;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> fetchRequests({
    String filter = "wall",
    int page = 1,
    int perPage = 20,
    bool refresh = false,
  }) async {
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final queryParams = {
        "filter": filter,
        "page": page.toString(),
        "per_page": perPage.toString(),
      };

      final res = await ApiService.get("prayers", queryParams: queryParams);

      if (res.statusCode == 200) {
        final body = ApiService.parseBody(res);
        final fetchedRequests = PrayerRequest.listFromJson(body['data']);

        if (refresh) _requests.clear();

        _requests.addAll(fetchedRequests);
        _hasMore = fetchedRequests.length >= perPage;
      } else {
        debugPrint("❌ fetchRequests failed: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ fetchRequests error: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createRequest({
    required String title,
    required String content,
    required bool isAnonymous,
    required String status,
    required String category,
  }) async {
    try {
      final res = await ApiService.post("prayers", {
        "title": title,
        "content": content,
        "is_anonymous": isAnonymous,
        "status": status,
        "category": category,
      });

      if (res.statusCode == 201) {
        final body = ApiService.parseBody(res);
        final newRequest = PrayerRequest.fromJson(body['data']);
        _requests.insert(0, newRequest);
        notifyListeners();
        return true;
      } else {
        debugPrint("❌ createRequest failed: ${res.statusCode}");
        return false;
      }
    } catch (e) {
      debugPrint("❌ createRequest error: $e");
      return false;
    }
  }

  Future<void> togglePrayerById(int prayerId) async {
    try {
      final endpoint = "prayers/$prayerId/toggle_prayer";
      final res = await ApiService.post(endpoint, {});

      if (res.statusCode == 200 || res.statusCode == 201) {
        final index = _requests.indexWhere((r) => r.id == prayerId);
        if (index != -1) {
          final req = _requests[index];
          final increment = !req.hasPrayed;
          _requests[index] = req.copyWith(
            prayersCount: req.prayersCount + (increment ? 1 : -1),
            hasPrayed: increment,
          );
          notifyListeners();
        }
      } else {
        debugPrint("❌ togglePrayer failed: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ togglePrayer error: $e");
    }
  }

  Future<void> deleteRequest(int prayerId) async {
    try {
      final res = await ApiService.delete("prayers/$prayerId");
      if (res.statusCode == 200) {
        _requests.removeWhere((r) => r.id == prayerId);
        notifyListeners();
      } else {
        debugPrint("❌ deleteRequest failed: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ deleteRequest error: $e");
    }
  }

  Future<void> toggleAnswered(
    int prayerId, {
    bool removeIfUnanswered = false,
  }) async {
    try {
      final index = _requests.indexWhere((r) => r.id == prayerId);
      if (index == -1) return;

      final req = _requests[index];
      final newStatus = req.status == "answered" ? "pending" : "answered";

      final res = await ApiService.patch("prayers/$prayerId", {
        "status": newStatus,
      });

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (removeIfUnanswered && newStatus == "pending") {
          _requests.removeAt(index);
        } else {
          _requests[index] = req.copyWith(status: newStatus);
        }
        notifyListeners();
      } else {
        debugPrint("❌ toggleAnswered failed: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ toggleAnswered error: $e");
    }
  }

  /// 🔹 Count prayers for a specific user
  Future<int> countUserPrayers(int userId) async {
    try {
      // If already fetched, use cache
      if (_requests.isNotEmpty) {
        return _requests.where((r) => r.userId == userId).length;
      }

      // Otherwise, fetch user-specific prayers
      final res = await ApiService.get(
        "prayers",
        queryParams: {"user_id": userId.toString()},
      );

      if (res.statusCode == 200) {
        final body = ApiService.parseBody(res);
        final userPrayers = PrayerRequest.listFromJson(body['data']);
        return userPrayers.length;
      } else {
        debugPrint("❌ countUserPrayers failed: ${res.statusCode}");
        return 0;
      }
    } catch (e) {
      debugPrint("❌ countUserPrayers error: $e");
      return 0;
    }
  }

  /// 🔹 Set the current logged-in user ID safely
  void setCurrentUserId(int? userId) {
    if (userId != null) {
      _currentUserId = userId;
      notifyListeners();
    } else {
      debugPrint("❌ setCurrentUserId called with null");
    }
  }
}
