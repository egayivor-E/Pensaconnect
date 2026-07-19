import 'package:flutter/material.dart' hide Badge;

import '../models/user.dart';
import '../models/badge.dart';
import '../repositories/auth_repository.dart';
import '../repositories/prayer_repository.dart';
import '../repositories/testimony_repository.dart';
import '../repositories/group_chat_repository.dart';

class ProfileViewModel extends ChangeNotifier {
  final AuthRepository authRepo;
  final PrayerRepository prayerRepo;
  final TestimonyRepository testimonyRepo;
  final GroupChatRepository groupRepo;

  User? user;
  bool isLoading = false;
  String? error;

  int prayersCount = 0;
  int testimoniesCount = 0;
  int groupsCount = 0;

  List<Badge> badges = [];

  ProfileViewModel({
    required this.authRepo,
    required this.prayerRepo,
    required this.testimonyRepo,
    required this.groupRepo,
  });

  Future<void> loadProfile() async {
    try {
      isLoading = true;
      error = null;
      notifyListeners();

      user = await authRepo.getCurrentUser();

      // ✅ Notify as soon as the user (and its avatar URL) is known, instead
      // of waiting on the three counts below. Previously this method only
      // called notifyListeners() at the very start and the very end, so a
      // freshly-saved profile picture sat fetched-but-unrendered for the
      // entire time it took prayers/testimonies/groups to also load —
      // three unrelated, sequential network calls the avatar had nothing
      // to do with. That's the "delay to render" after saving.
      isLoading = false;
      notifyListeners();

      // Counts are independent of each other, so fetch them concurrently
      // rather than one-by-one, and let any single failure default to 0
      // instead of blanking out the whole profile.
      final results = await Future.wait([
        prayerRepo.countUserPrayers(user!.id).catchError((_) => 0),
        testimonyRepo.countUserTestimonies(user!.id).catchError((_) => 0),
        groupRepo.getGroups().then((g) => g.length).catchError((_) => 0),
      ]);
      prayersCount = results[0];
      testimoniesCount = results[1];
      groupsCount = results[2];

      badges = computeBadges(
        prayersCount: prayersCount,
        testimoniesCount: testimoniesCount,
        groupsCount: groupsCount,
        createdAt: user?.createdAt,
      );
    } catch (e) {
      error = e.toString();
      isLoading = false;
    } finally {
      notifyListeners();
    }
  }
}
