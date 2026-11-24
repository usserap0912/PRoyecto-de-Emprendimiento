import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

// ============================================================
// NAV ICONS — Iconos de la barra de navegación
// ============================================================
// Set redondeado y moderno. El icono activo se apoya en una píldora
// translúcida del color de su sección; el inactivo queda en gris.
// ============================================================

enum AnimatedNavIconType {
  muro,
  mapa,
  sos,
  chat,
  reportar,
}

/// Icono para la navegación inferior con estado activo resaltado.
class AnimatedNavIcon extends StatelessWidget {
  final AnimatedNavIconType type;
  final bool isActive;
  final double size;

  const AnimatedNavIcon({
    super.key,
    required this.type,
    this.isActive = false,
    this.size = 23,
  });

  /// Color propio de cada sección.
  Color _colorForType(AnimatedNavIconType type) {
    return switch (type) {
      AnimatedNavIconType.muro => AppTheme.brandRedBright,
      AnimatedNavIconType.mapa => const Color(0xFF2E7D32),
      AnimatedNavIconType.sos => AppTheme.sosRed,
      AnimatedNavIconType.chat => const Color(0xFF00796B),
      AnimatedNavIconType.reportar => const Color(0xFFEF6C00),
    };
  }

  IconData _iconFor(AnimatedNavIconType type) {
    return switch (type) {
      AnimatedNavIconType.muro =>
        isActive ? Icons.dashboard_rounded : Icons.dashboard_outlined,
      AnimatedNavIconType.mapa =>
        isActive ? Icons.explore_rounded : Icons.explore_outlined,
      AnimatedNavIconType.sos => Icons.emergency_rounded,
      AnimatedNavIconType.chat =>
        isActive ? Icons.forum_rounded : Icons.forum_outlined,
      AnimatedNavIconType.reportar => Icons.add_location_alt_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isActive
        ? _colorForType(type)
        : (isDark ? Colors.grey[500]! : Colors.grey[400]!);

    return SizedBox(
      width: 42,
      height: 28,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 42,
          height: 28,
          decoration: BoxDecoration(
            color: isActive
                ? _colorForType(type).withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(_iconFor(type), size: size, color: color),
        ),
      ),
    );
  }
}
