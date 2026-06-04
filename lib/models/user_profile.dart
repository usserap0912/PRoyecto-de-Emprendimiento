class UserProfile {
  final String id;
  final String userCode;
  final int zone;
  final DateTime createdAt;
  final bool isActive;

  UserProfile({
    required this.id,
    required this.userCode,
    required this.zone,
    required this.createdAt,
    this.isActive = true,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      userCode: map['user_code'] as String,
      zone: map['zone'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_code': userCode,
      'zone': zone,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }
}
