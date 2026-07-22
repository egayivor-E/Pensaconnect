import 'package:pensaconnect/services/api_service.dart';

class User {
  final int id;
  final String username;
  final String email;
  final String? profilePicture;
  final List<String> roles;
  final DateTime? createdAt;

  // Number of active group chats *this* user belongs to — comes straight
  // from User.to_dict() on the backend (backend/models.py), which computes
  // it from the fetched user's own group_memberships, not the caller's.
  // Use this instead of GroupChatRepository.getGroups() when showing
  // someone else's profile: getGroups() always hits GET /group-chats/,
  // which is scoped to the *logged-in* user via the JWT, so calling it on
  // another person's profile silently displayed the viewer's own group
  // count instead of theirs.
  final int groupChatsCount;

  // Whether an admin has explicitly granted this user permission to start
  // their own live broadcast (see LiveBroadcastRepository.setBroadcastPermission
  // / backend PATCH /users/<id>/broadcast-permission). Admins can always go
  // live regardless of this flag — see AuthProvider's UserModel.canStartBroadcast
  // for the equivalent check on the *current* user.
  final bool canGoLive;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.profilePicture,
    required this.roles,
    this.createdAt,
    this.groupChatsCount = 0,
    this.canGoLive = false,
  });

  // ✅ Better approach - accept baseUrl as parameter
  String getProfilePictureUrl(String baseUrl) {
    final pic = profilePicture;
    if (pic == null || pic.isEmpty) {
      return '$baseUrl/uploads/default-avatar.png';
    }

    // Already an absolute URL (e.g. Supabase storage) — use as-is.
    if (pic.startsWith('http://') || pic.startsWith('https://')) {
      return pic;
    }

    final normalizedPath = pic.startsWith('/') ? pic.substring(1) : pic;
    return '$baseUrl/$normalizedPath';
  }

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
      groupChatsCount: (json['group_chats_count'] as num?)?.toInt() ?? 0,
      canGoLive: json['can_go_live'] == true,
    );
  }

  /// Returns a copy with the given fields overridden — used to reflect an
  /// admin's broadcast-permission toggle immediately without a full refetch.
  User copyWith({bool? canGoLive}) {
    return User(
      id: id,
      username: username,
      email: email,
      profilePicture: profilePicture,
      roles: roles,
      createdAt: createdAt,
      groupChatsCount: groupChatsCount,
      canGoLive: canGoLive ?? this.canGoLive,
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
      'can_go_live': canGoLive,
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
