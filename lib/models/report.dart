import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

class Report {
  final String id;
  final String userCode;
  final int zone;
  final String category;
  final String description;
  final String? imageUrl;
  final String? videoUrl;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String tag;
  final String status;
  final DateTime createdAt;
  final int shieldCount;
  final int alertCount;
  final int checkCount;

  Report({
    required this.id,
    required this.userCode,
    required this.zone,
    required this.category,
    required this.description,
    this.imageUrl,
    this.videoUrl,
    this.latitude,
    this.longitude,
    this.address,
    required this.tag,
    this.status = 'activo',
    required this.createdAt,
    this.shieldCount = 0,
    this.alertCount = 0,
    this.checkCount = 0,
  });

  factory Report.fromMap(Map<String, dynamic> map) {
    return Report(
      id: map['id'] as String,
      userCode: map['user_code'] as String,
      zone: map['zone'] as int,
      category: map['category'] as String,
      description: map['description'] as String,
      imageUrl: map['image_url'] as String?,
      videoUrl: map['video_url'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      address: map['address'] as String?,
      tag: map['tag'] as String,
      status: map['status'] as String? ?? 'activo',
      createdAt: DateTime.parse(map['created_at'] as String),
      shieldCount: map['shield_count'] as int? ?? 0,
      alertCount: map['alert_count'] as int? ?? 0,
      checkCount: map['check_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_code': userCode,
      'zone': zone,
      'category': category,
      'description': description,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'tag': tag,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'shield_count': shieldCount,
      'alert_count': alertCount,
      'check_count': checkCount,
    };
  }

  // ================================================================
  // TAG helpers
  // ================================================================

  String get tagLabel => tagLabelFor(tag);

  static String tagLabelFor(String tag) {
    switch (tag) {
      case 'rojo':
        return 'Peligro Grave';
      case 'amarillo':
        return 'Alerta Preventiva';
      case 'verde':
        return 'Información / situación positiva';
      default:
        return tag;
    }
  }

  Color get tagColor {
    return tagColorFor(tag);
  }

  static Color tagColorFor(String tag) {
    switch (tag) {
      case 'rojo':
        return const Color(0xFFD32F2F);
      case 'amarillo':
        return const Color(0xFFFFA000);
      case 'verde':
        return const Color(0xFF388E3C);
      default:
        return Colors.grey;
    }
  }

  // ================================================================
  // CATEGORY helpers (static para reuso sin instancia)
  // ================================================================

  String get categoryLabel => categoryLabelFor(category);

  static String categoryLabelFor(String category) {
    switch (category) {
      case 'robo':
        return 'Robo';
      case 'sos':
        return '🚨 S.O.S.';
      case 'sospechoso':
        return 'Actividad sospechosa';
      case 'extorsion':
        return 'Extorsión / Amenaza';
      case 'alumbrado':
        return 'Falla de alumbrado';
      default:
        return 'Otros';
    }
  }

  static IconData categoryIconFor(String category) {
    switch (category) {
      case 'robo':
        return Icons.gpp_bad_outlined;
      case 'sos':
        return Icons.sos;
      case 'sospechoso':
        return Icons.visibility_outlined;
      case 'extorsion':
        return Icons.warning_amber_rounded;
      case 'alumbrado':
        return Icons.lightbulb_outline;
      default:
        return Icons.more_horiz_rounded;
    }
  }

  static Color categoryColorFor(String category) {
    switch (category) {
      case 'robo':
        return const Color(0xFFD32F2F);
      case 'sos':
        return AppTheme.sosRed; // Color SOS intenso
      case 'extorsion':
        return const Color(0xFFD32F2F);
      case 'sospechoso':
        return const Color(0xFFFFA000);
      case 'alumbrado':
        return const Color(0xFFFFA000);
      default:
        return Colors.grey;
    }
  }
}
