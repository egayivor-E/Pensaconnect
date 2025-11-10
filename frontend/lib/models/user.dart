class User {
  final int id;
  final String username;
  final String email;
  final String? profilePicture;
  final List<String> roles;
  final DateTime? createdAt; // 👈 new field

  User({
    required this.id,
    required this.username,
    required this.email,
    this.profilePicture,
    required this.roles,
    this.createdAt,
  });

  /// ✅ Factory constructor handles both int and string for `id`
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: _parseId(json['id']),
      username: (json['username'] ?? json['full_name'] ?? '') as String,
      email: json['email'] as String,
      profilePicture: json['profile_picture'] as String?,
      roles: (json['roles'] as List<dynamic>).map((r) => r.toString()).toList(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'profile_picture': profilePicture,
      'roles': roles,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  String getFullName() => username;

  /// ✅ Computed getter for String version of id
  String get idString => id.toString();

  /// ✅ Safe parser for id (handles both String and int)
  static int _parseId(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    throw ArgumentError('Invalid type for id: ${value.runtimeType}');
  }
}
