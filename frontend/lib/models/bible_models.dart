// lib/models/bible_models.dart
import 'dart:convert';

/// A small helper to parse DateTime safely.
DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}

/// Reading Progress model
class ReadingProgress {
  final int itemId;
  final String itemType; // 'devotion', 'study_plan', 'archive'
  final double progress; // 0.0 to 1.0
  final int currentPage;
  final int totalPages;
  final DateTime lastRead;
  final bool isCompleted;
  final Duration? readingTime;

  const ReadingProgress({
    required this.itemId,
    required this.itemType,
    required this.progress,
    required this.currentPage,
    required this.totalPages,
    required this.lastRead,
    required this.isCompleted,
    this.readingTime,
  });

  factory ReadingProgress.initial(int itemId, String itemType, int totalPages) {
    return ReadingProgress(
      itemId: itemId,
      itemType: itemType,
      progress: 0.0,
      currentPage: 0,
      totalPages: totalPages,
      lastRead: DateTime.now(),
      isCompleted: false,
    );
  }

  factory ReadingProgress.fromJson(Map<String, dynamic> json) =>
      ReadingProgress(
        itemId: (json['itemId'] ?? 0) as int,
        itemType: (json['itemType'] ?? '') as String,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        currentPage: (json['currentPage'] ?? 0) as int,
        totalPages: (json['totalPages'] ?? 1) as int,
        lastRead: _parseDate(json['lastRead']) ?? DateTime.now(),
        isCompleted: (json['isCompleted'] ?? false) as bool,
        readingTime: json['readingTime'] != null
            ? Duration(seconds: (json['readingTime'] as num).toInt())
            : null,
      );

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'itemType': itemType,
    'progress': progress,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'lastRead': lastRead.toIso8601String(),
    'isCompleted': isCompleted,
    if (readingTime != null) 'readingTime': readingTime!.inSeconds,
  };

  ReadingProgress copyWith({
    double? progress,
    int? currentPage,
    int? totalPages,
    DateTime? lastRead,
    bool? isCompleted,
    Duration? readingTime,
  }) {
    return ReadingProgress(
      itemId: itemId,
      itemType: itemType,
      progress: progress ?? this.progress,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      lastRead: lastRead ?? this.lastRead,
      isCompleted: isCompleted ?? this.isCompleted,
      readingTime: readingTime ?? this.readingTime,
    );
  }

  static List<ReadingProgress> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .map((e) => ReadingProgress.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is String) {
      try {
        final parsed = jsonDecode(data) as List<dynamic>;
        return parsed
            .map((e) => ReadingProgress.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const <ReadingProgress>[];
      }
    }
    return const <ReadingProgress>[];
  }
}

/// Devotion model with progress tracking
class Devotion {
  final int id;
  final String verse;
  final String content;
  final String? reflection;
  final String? prayer;
  final DateTime? date;
  final ReadingProgress? progress;
  final int estimatedReadingMinutes;

  const Devotion({
    required this.id,
    required this.verse,
    required this.content,
    this.reflection,
    this.prayer,
    this.date,
    this.progress,
    this.estimatedReadingMinutes = 5,
  });

  factory Devotion.fromJson(Map<String, dynamic> json) => Devotion(
    id: (json['id'] ?? 0) as int,
    verse: (json['verse'] ?? '') as String,
    content: (json['content'] ?? '') as String,
    reflection: json['reflection'] as String?,
    prayer: json['prayer'] as String?,
    date: _parseDate(json['date']),
    progress: json['progress'] != null
        ? ReadingProgress.fromJson(json['progress'] as Map<String, dynamic>)
        : null,
    estimatedReadingMinutes: (json['estimatedReadingMinutes'] ?? 5) as int,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'verse': verse,
    'content': content,
    'reflection': reflection,
    'prayer': prayer,
    'date': date?.toIso8601String(),
    if (progress != null) 'progress': progress!.toJson(),
    'estimatedReadingMinutes': estimatedReadingMinutes,
  };

  Devotion copyWith({
    ReadingProgress? progress,
    String? verse,
    String? content,
    String? reflection,
    String? prayer,
  }) {
    return Devotion(
      id: id,
      verse: verse ?? this.verse,
      content: content ?? this.content,
      reflection: reflection ?? this.reflection,
      prayer: prayer ?? this.prayer,
      date: date,
      progress: progress ?? this.progress,
      estimatedReadingMinutes: estimatedReadingMinutes,
    );
  }

  bool get isCompleted => progress?.isCompleted ?? false;
  double get completionPercentage => progress?.progress ?? 0.0;
  bool get isStarted => (progress?.progress ?? 0.0) > 0.0;

  static List<Devotion> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .map((e) => Devotion.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is String) {
      try {
        final parsed = jsonDecode(data) as List<dynamic>;
        return parsed
            .map((e) => Devotion.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const <Devotion>[];
      }
    }
    return const <Devotion>[];
  }
}

enum StudyPlanDifficulty { beginner, intermediate, advanced }

/// Study Plan model with progress tracking
class StudyPlan {
  final int id;
  final String title;
  final String description;
  final List<String> verses;
  final int? dayCount;
  final DateTime? createdAt;
  final ReadingProgress? progress;
  final List<StudyPlanDay>? days;
  final int totalLessons;
  // Add this field to your StudyPlan class
  final StudyPlanDifficulty? difficulty;

  const StudyPlan({
    required this.id,
    required this.title,
    required this.description,
    required this.verses,
    this.dayCount,
    this.createdAt,
    this.progress,
    this.days,
    this.totalLessons = 1,
    this.difficulty, // Add this parameter
  });

  // Update your fromJson method
  factory StudyPlan.fromJson(Map<String, dynamic> json) => StudyPlan(
    id: (json['id'] ?? 0) as int,
    title: (json['title'] ?? '') as String,
    description: (json['description'] ?? '') as String,
    verses: ((json['verses'] as List?) ?? const <dynamic>[])
        .map((e) => e.toString())
        .toList(),
    dayCount: json['dayCount'] is int
        ? json['dayCount'] as int
        : int.tryParse('${json['dayCount'] ?? ''}'),
    createdAt: _parseDate(json['createdAt']),
    progress: json['progress'] != null
        ? ReadingProgress.fromJson(json['progress'] as Map<String, dynamic>)
        : null,
    days: json['days'] != null ? StudyPlanDay.listFromJson(json['days']) : null,
    totalLessons: (json['totalLessons'] ?? 1) as int,
    difficulty: json['difficulty'] != null
        ? StudyPlanDifficulty.values.firstWhere(
            (e) => e.toString() == 'StudyPlanDifficulty.${json['difficulty']}',
            orElse: () => StudyPlanDifficulty.beginner,
          )
        : null,
  );

  // Update your toJson method
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'verses': verses,
    'dayCount': dayCount,
    'createdAt': createdAt?.toIso8601String(),
    if (progress != null) 'progress': progress!.toJson(),
    if (days != null) 'days': days!.map((day) => day.toJson()).toList(),
    'totalLessons': totalLessons,
    if (difficulty != null) 'difficulty': difficulty.toString().split('.').last,
  };

  // Update your copyWith method
  StudyPlan copyWith({
    ReadingProgress? progress,
    List<StudyPlanDay>? days,
    StudyPlanDifficulty? difficulty,
  }) {
    return StudyPlan(
      id: id,
      title: title,
      description: description,
      verses: verses,
      dayCount: dayCount,
      createdAt: createdAt,
      progress: progress ?? this.progress,
      days: days ?? this.days,
      totalLessons: totalLessons,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  // ... rest of your StudyPlan class ...

  bool get isCompleted => progress?.isCompleted ?? false;
  double get completionPercentage => progress?.progress ?? 0.0;
  int get completedLessons {
    if (days == null) return 0;
    return days!.where((day) => day.isCompleted).length;
  }

  static List<StudyPlan> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .map((e) => StudyPlan.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is String) {
      try {
        final parsed = jsonDecode(data) as List<dynamic>;
        return parsed
            .map((e) => StudyPlan.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const <StudyPlan>[];
      }
    }
    return const <StudyPlan>[];
  }
}

/// Study Plan Day model for tracking daily progress
class StudyPlanDay {
  final int dayNumber;
  final String title;
  final String content;
  final List<String> verses;
  final bool isCompleted;
  final DateTime? completedAt;
  final Duration? readingTime;

  const StudyPlanDay({
    required this.dayNumber,
    required this.title,
    required this.content,
    required this.verses,
    this.isCompleted = false,
    this.completedAt,
    this.readingTime,
  });

  factory StudyPlanDay.fromJson(Map<String, dynamic> json) => StudyPlanDay(
    dayNumber: (json['dayNumber'] ?? 0) as int,
    title: (json['title'] ?? '') as String,
    content: (json['content'] ?? '') as String,
    verses: ((json['verses'] as List?) ?? const <dynamic>[])
        .map((e) => e.toString())
        .toList(),
    isCompleted: (json['isCompleted'] ?? false) as bool,
    completedAt: _parseDate(json['completedAt']),
    readingTime: json['readingTime'] != null
        ? Duration(seconds: (json['readingTime'] as num).toInt())
        : null,
  );

  Map<String, dynamic> toJson() => {
    'dayNumber': dayNumber,
    'title': title,
    'content': content,
    'verses': verses,
    'isCompleted': isCompleted,
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (readingTime != null) 'readingTime': readingTime!.inSeconds,
  };

  StudyPlanDay copyWith({
    bool? isCompleted,
    DateTime? completedAt,
    Duration? readingTime,
  }) {
    return StudyPlanDay(
      dayNumber: dayNumber,
      title: title,
      content: content,
      verses: verses,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      readingTime: readingTime ?? this.readingTime,
    );
  }

  static List<StudyPlanDay> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .map((e) => StudyPlanDay.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is String) {
      try {
        final parsed = jsonDecode(data) as List<dynamic>;
        return parsed
            .map((e) => StudyPlanDay.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const <StudyPlanDay>[];
      }
    }
    return const <StudyPlanDay>[];
  }
}

/// Archive Item model with progress tracking
class ArchiveItem {
  final int id;
  final String title;
  final String description;
  final DateTime date;
  final ReadingProgress? progress;
  final String? category;
  final int estimatedReadingMinutes;

  const ArchiveItem({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    this.progress,
    this.category,
    this.estimatedReadingMinutes = 10,
  });

  factory ArchiveItem.fromJson(Map<String, dynamic> json) => ArchiveItem(
    id: (json['id'] ?? 0) as int,
    title: (json['title'] ?? '') as String,
    description: (json['description'] ?? '') as String,
    date: _parseDate(json['date']) ?? DateTime.now(),
    progress: json['progress'] != null
        ? ReadingProgress.fromJson(json['progress'] as Map<String, dynamic>)
        : null,
    category: json['category'] as String?,
    estimatedReadingMinutes: (json['estimatedReadingMinutes'] ?? 10) as int,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'date': date.toIso8601String(),
    if (progress != null) 'progress': progress!.toJson(),
    if (category != null) 'category': category,
    'estimatedReadingMinutes': estimatedReadingMinutes,
  };

  ArchiveItem copyWith({ReadingProgress? progress}) {
    return ArchiveItem(
      id: id,
      title: title,
      description: description,
      date: date,
      progress: progress ?? this.progress,
      category: category,
      estimatedReadingMinutes: estimatedReadingMinutes,
    );
  }

  bool get isCompleted => progress?.isCompleted ?? false;
  double get completionPercentage => progress?.progress ?? 0.0;

  static List<ArchiveItem> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .map((e) => ArchiveItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is String) {
      try {
        final parsed = jsonDecode(data) as List<dynamic>;
        return parsed
            .map((e) => ArchiveItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const <ArchiveItem>[];
      }
    }
    return const <ArchiveItem>[];
  }
}

/// User Reading Statistics
class UserReadingStats {
  final int totalItemsRead;
  final int totalReadingTime; // in minutes
  final int currentStreak;
  final int longestStreak;
  final Map<String, int>
  itemsByType; // {'devotion': 5, 'study_plan': 2, 'archive': 1}
  final DateTime lastRead;

  const UserReadingStats({
    required this.totalItemsRead,
    required this.totalReadingTime,
    required this.currentStreak,
    required this.longestStreak,
    required this.itemsByType,
    required this.lastRead,
  });

  factory UserReadingStats.fromJson(Map<String, dynamic> json) =>
      UserReadingStats(
        totalItemsRead: (json['totalItemsRead'] ?? 0) as int,
        totalReadingTime: (json['totalReadingTime'] ?? 0) as int,
        currentStreak: (json['currentStreak'] ?? 0) as int,
        longestStreak: (json['longestStreak'] ?? 0) as int,
        itemsByType: Map<String, int>.from(json['itemsByType'] ?? {}),
        lastRead: _parseDate(json['lastRead']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
    'totalItemsRead': totalItemsRead,
    'totalReadingTime': totalReadingTime,
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
    'itemsByType': itemsByType,
    'lastRead': lastRead.toIso8601String(),
  };

  double get averageReadingTimePerItem {
    if (totalItemsRead == 0) return 0.0;
    return totalReadingTime / totalItemsRead;
  }
}
