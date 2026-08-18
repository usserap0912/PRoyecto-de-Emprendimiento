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

  static SosAlert? tryFromMap(Map<String, dynamic> map) {
    final latitude = map['latitude'];
    final longitude = map['longitude'];
    final createdAt = DateTime.tryParse(map['created_at'] as String? ?? '');
    if (map['id'] is! String ||
        map['user_code'] is! String ||
        latitude is! num ||
        longitude is! num ||
        createdAt == null) {
      return null;
    }
    return SosAlert(
      id: map['id'] as String,
      userCode: map['user_code'] as String,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      address: null,
      status: map['status'] as String? ?? 'activo',
      createdAt: createdAt,
    );
  }

  bool isPubliclyActiveAt(DateTime now) =>
      status == 'activo' &&
      !createdAt.isAfter(now.add(const Duration(seconds: 5))) &&
      now.difference(createdAt) <= const Duration(seconds: 75);

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
