class SosAlert {
  final String id;
  final String userCode;
  final double latitude;
  final double longitude;
  final String? address;
  final String status; // 'activo', 'cancelado', 'atendido'
  final DateTime createdAt;

  SosAlert({
    required this.id,
    required this.userCode,
    required this.latitude,
    required this.longitude,
    this.address,
    this.status = 'activo',
    required this.createdAt,
  });

  factory SosAlert.fromMap(Map<String, dynamic> map) {
    return SosAlert(
      id: map['id'] as String,
      userCode: map['user_code'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      address: map['address'] as String?,
      status: map['status'] as String? ?? 'activo',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_code': userCode,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
