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
      prayersCount = await prayerRepo.countUserPrayers(user!.id);
      testimoniesCount = await testimonyRepo.countUserTestimonies(
        user!.id as String,
      );
      groupsCount = (await groupRepo.getGroups()).length;

      badges = _determineBadges();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 🔹 Compute dynamic badges
  List<Badge> _determineBadges() {
    final badgeList = <Badge>[];

    if (prayersCount > 0) {
      badgeList.add(
        const Badge(
          title: "Prayer Warrior",
          icon: Icons.favorite,
          color: Colors.red,
        ),
      );
    }

    if (testimoniesCount > 0) {
      badgeList.add(
        const Badge(
          title: "Testifier",
          icon: Icons.record_voice_over,
          color: Colors.blue,
        ),
      );
    }

    if (groupsCount >= 3) {
      badgeList.add(
        const Badge(
          title: "Community Builder",
          icon: Icons.group,
          color: Colors.purple,
        ),
      );
    }

    if (prayersCount >= 50) {
      badgeList.add(
        const Badge(
          title: "Faithful Servant",
          icon: Icons.emoji_events,
          color: Colors.amber,
        ),
      );
    }

    if (user != null && user!.createdAt != null) {
      badgeList.add(
        const Badge(title: "Pioneer", icon: Icons.star, color: Colors.green),
      );
    }

    return badgeList;
  }
}
