import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

// ============================================================
// NAV ICONS — Iconos de la barra de navegación (estáticos)
// ============================================================
// Sin animaciones continuas: los iconos ya no pulsan, rebotan ni giran.
// Solo cambia el color según estén activos o inactivos.
// ============================================================

enum AnimatedNavIconType {
  muro,
  mapa,
  sos,
  chat,
  reportar,
  premium,
}

/// Icono para la navegación inferior. Estático, sin movimiento.
class AnimatedNavIcon extends StatelessWidget {
  final AnimatedNavIconType type;
  final bool isActive;
  final double size;

  const AnimatedNavIcon({
    super.key,
    required this.type,
    this.isActive = false,
    this.size = 22,
  });

  /// Retorna el color personalizado para cada sección
  Color _colorForType(AnimatedNavIconType type) {
    return switch (type) {
      AnimatedNavIconType.muro => const Color(0xFF1976D2),     // Azul
      AnimatedNavIconType.mapa => const Color(0xFF388E3C),      // Verde
      AnimatedNavIconType.sos => AppTheme.sosRed,               // Rojo SOS
      AnimatedNavIconType.chat => const Color(0xFF00897B),      // Teal
      AnimatedNavIconType.reportar => const Color(0xFFF57C00),  // Naranja
      AnimatedNavIconType.premium => Colors.amber,               // Amarillo
    };
  }

  IconData _iconFor(AnimatedNavIconType type) {
    return switch (type) {
      AnimatedNavIconType.muro =>
        isActive ? Icons.newspaper : Icons.newspaper_outlined,
      AnimatedNavIconType.mapa => Icons.map,
      AnimatedNavIconType.sos => Icons.sos,
      AnimatedNavIconType.chat => Icons.chat,
      AnimatedNavIconType.reportar => Icons.add_circle,
      AnimatedNavIconType.premium => Icons.star,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isActive
        ? _colorForType(type)
        : (isDark ? Colors.grey[500]! : Colors.grey[400]!);

    return Icon(_iconFor(type), size: size, color: color);
  }
}
