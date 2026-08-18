class IdentityProfile {
  const IdentityProfile({
    required this.userCode,
    required this.zone,
    this.authUserId,
  });

  factory IdentityProfile.fromMap(Map<String, dynamic> map) {
    return IdentityProfile(
      authUserId: map['auth_user_id'] as String?,
      userCode: map['user_code'] as String,
      zone: (map['zone'] as num).toInt(),
    );
  }

  final String? authUserId;
  final String userCode;
  final int zone;
}
