// lib/models/member.dart
class Member {
  final String id;
  final String name;
  final String? profileImage;
  final bool isOnline;

  Member({
    required this.id,
    required this.name,
    this.profileImage,
    this.isOnline = false,
  });

  /// Factory constructor for creating a `Member` instance from JSON
  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      name: json['name'] as String,
      profileImage: json['profileImage'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  /// Convert a `Member` instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (profileImage != null) 'profileImage': profileImage,
      'isOnline': isOnline,
    };
  }
}
