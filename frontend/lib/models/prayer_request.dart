class PrayerRequest {
  final int id;
  final int userId;
  final String? username;
  final String? userProfilePic;
  final String title;
  final String content;
  final bool isAnonymous;
  final String status; // "mutable; pending" or "answered"
  final int prayersCount;
  final String? category;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool hasPrayed; // tracks if current user has prayed

  PrayerRequest({
    required this.id,
    required this.userId,
    this.username,
    this.userProfilePic,
    required this.title,
    required this.content,
    required this.isAnonymous,
    required this.status,
    this.prayersCount = 0,
    this.category,
    required this.createdAt,
    this.updatedAt,
    this.hasPrayed = false,
  });

  factory PrayerRequest.fromJson(Map<String, dynamic> json) {
    return PrayerRequest(
      id: json['id'],
      userId: json['user_id'],
      username: json['username'],
      userProfilePic: json['user_profile_pic'],
      title: json['title'],
      content: json['content'],
      isAnonymous: json['is_anonymous'] ?? false,
      status: json['status'] ?? "pending",
      prayersCount: json['prayers_count'] ?? 0,
      category: json['category'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      hasPrayed: json['has_prayed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'user_profile_pic': userProfilePic,
      'title': title,
      'content': content,
      'is_anonymous': isAnonymous,
      'status': status,
      'prayers_count': prayersCount,
      'category': category,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'has_prayed': hasPrayed,
    };
  }

  PrayerRequest copyWith({
    int? prayersCount,
    String? status,
    bool? hasPrayed,
    String? userProfilePic,
    String? title,
    String? content,
    bool? isAnonymous,
    String? category,
  }) {
    return PrayerRequest(
      id: id,
      userId: userId,
      username: username,
      userProfilePic: userProfilePic ?? this.userProfilePic,
      title: title ?? this.title,
      content: content ?? this.content,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      status: status ?? this.status,
      prayersCount: prayersCount ?? this.prayersCount,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: updatedAt,
      hasPrayed: hasPrayed ?? this.hasPrayed,
    );
  }

  static List<PrayerRequest> listFromJson(List<dynamic> list) {
    return list.map((json) => PrayerRequest.fromJson(json)).toList();
  }
}
