import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

@immutable
class ReportCategoryOption {
  final String value;
  final String label;
  final IconData fallbackIcon;
  final Color color;
  final String? illustrationAsset;

  const ReportCategoryOption({
    required this.value,
    required this.label,
    required this.fallbackIcon,
    required this.color,
    this.illustrationAsset,
  });
}

@immutable
class ReportSeverityOption {
  final String value;
  final String label;
  final String description;
  final Color color;

  const ReportSeverityOption({
    required this.value,
    required this.label,
    required this.description,
    required this.color,
  });
}

abstract final class ReportFormConfig {
  /// `illustrationAsset` remains null until the approved 3D illustrations are
  /// supplied. The UI uses the explicit Material icon fallback meanwhile.
  static const categories = <ReportCategoryOption>[
    ReportCategoryOption(
      value: 'robo',
      label: 'Robo',
      fallbackIcon: Icons.gpp_bad_outlined,
      color: AppTheme.dangerRed,
    ),
    ReportCategoryOption(
      value: 'sospechoso',
      label: 'Actividad sospechosa',
      fallbackIcon: Icons.visibility_outlined,
      color: AppTheme.warningYellow,
    ),
    ReportCategoryOption(
      value: 'extorsion',
      label: 'Extorsión / Amenaza',
      fallbackIcon: Icons.warning_amber_rounded,
      color: AppTheme.dangerRed,
    ),
    ReportCategoryOption(
      value: 'alumbrado',
      label: 'Falla de alumbrado',
      fallbackIcon: Icons.lightbulb_outline_rounded,
      color: AppTheme.warningYellow,
    ),
    ReportCategoryOption(
      value: 'otros',
      label: 'Otros',
      fallbackIcon: Icons.more_horiz_rounded,
      color: Colors.grey,
    ),
  ];

  static const severities = <ReportSeverityOption>[
    ReportSeverityOption(
      value: 'rojo',
      label: 'Peligro grave',
      description: 'Robo, extorsión, amenaza o peligro inmediato',
      color: Color(0xFFD32F2F),
    ),
    ReportSeverityOption(
      value: 'amarillo',
      label: 'Alerta preventiva',
      description: 'Actividad sospechosa o situación que requiere precaución',
      color: Color(0xFFFFA000),
    ),
    ReportSeverityOption(
      value: 'verde',
      label: 'Información / situación positiva',
      description:
          'Información comunitaria, situación resuelta o aviso positivo',
      color: Color(0xFF388E3C),
    ),
  ];

  static const supportedCategoryValues = <String>{
    'robo',
    'sospechoso',
    'extorsion',
    'alumbrado',
    'otros',
  };

  static const supportedSeverityValues = <String>{'rojo', 'amarillo', 'verde'};
}
