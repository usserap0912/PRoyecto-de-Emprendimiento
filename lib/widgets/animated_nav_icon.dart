import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

// ============================================================
// ANIMATED NAV ICONS — Animación continua con controllers ligeros
// ============================================================
// Cada icono tiene su propio AnimationController pequeno (~200 bytes).
// Se descartan automáticamente al salir de pantalla via dispose().
// ============================================================

enum AnimatedNavIconType {
  muro,
  mapa,
  sos,
  chat,
  reportar,
  premium,
}

/// Icono animado para navegación inferior.
/// Cada instancia tiene 1 AnimationController que se descarta al salir.
class AnimatedNavIcon extends StatefulWidget {
  final AnimatedNavIconType type;
  final bool isActive;
  final double size;

  const AnimatedNavIcon({
    super.key,
    required this.type,
    this.isActive = false,
    this.size = 22,
  });

  @override
  State<AnimatedNavIcon> createState() => _AnimatedNavIconState();
}

class _AnimatedNavIconState extends State<AnimatedNavIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final duration = switch (widget.type) {
      AnimatedNavIconType.muro => const Duration(milliseconds: 1500),
      AnimatedNavIconType.mapa => const Duration(milliseconds: 1200),
      AnimatedNavIconType.sos => const Duration(milliseconds: 600),
      AnimatedNavIconType.chat => const Duration(milliseconds: 1000),
      AnimatedNavIconType.reportar => const Duration(seconds: 3),
      AnimatedNavIconType.premium => const Duration(milliseconds: 800),
    };
    // reportar gira continuamente sin reversa; los demás van y vienen
    _controller = AnimationController(vsync: this, duration: duration)
      ..repeat(reverse: widget.type != AnimatedNavIconType.reportar);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.isActive
        ? _colorForType(widget.type)
        : (isDark ? Colors.grey[500]! : Colors.grey[400]!);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => _buildIcon(_controller.value, color),
    );
  }

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

  Widget _buildIcon(double value, Color color) {
    return switch (widget.type) {
      AnimatedNavIconType.muro => _muroIcon(value, color),
      AnimatedNavIconType.mapa => _mapaIcon(value, color),
      AnimatedNavIconType.sos => _sosIcon(value, color),
      AnimatedNavIconType.chat => _chatIcon(value, color),
      AnimatedNavIconType.reportar => _reportarIcon(value, color),
      AnimatedNavIconType.premium => _premiumIcon(value, color),
    };
  }

  // ============================================================
  // MURO — Pulso suave + outline/filled
  // ============================================================
  Widget _muroIcon(double value, Color color) {
    final scale = 1.0 + (value * 0.08);
    return Transform.scale(
      scale: scale,
      child: Icon(
        widget.isActive ? Icons.newspaper : Icons.newspaper_outlined,
        size: widget.size,
        color: color,
      ),
    );
  }

  // ============================================================
  // MAPA — Rebote sinusoidal
  // ============================================================
  Widget _mapaIcon(double value, Color color) {
    final bounce = math.sin(value * math.pi * 2) * 2.0;
    return Transform.translate(
      offset: Offset(0, bounce),
      child: Icon(Icons.map, size: widget.size, color: color),
    );
  }

  // ============================================================
  // S.O.S. — Pulso intenso + vibración
  // ============================================================
  Widget _sosIcon(double value, Color color) {
    final scale = 1.0 + (value * 0.2);
    final shake = math.sin(value * math.pi * 4) * 0.15;
    return Transform.rotate(
      angle: shake,
      child: Transform.scale(
        scale: scale,
        child: Icon(Icons.sos, size: widget.size, color: color),
      ),
    );
  }

  // ============================================================
  // CHAT — Respiración
  // ============================================================
  Widget _chatIcon(double value, Color color) {
    final breathe = 1.0 + (value * 0.06);
    return Transform.scale(
      scale: breathe,
      child: Icon(Icons.chat, size: widget.size, color: color),
    );
  }

  // ============================================================
  // REPORTAR — Giro continuo
  // ============================================================
  Widget _reportarIcon(double value, Color color) {
    return Transform.rotate(
      angle: value * math.pi * 2,
      child: Icon(Icons.add_circle, size: widget.size, color: color),
    );
  }

  // ============================================================
  // PREMIUM — Estrella con halo pulsante
  // ============================================================
  Widget _premiumIcon(double value, Color color) {
    final scale = 1.0 + (value * 0.18);
    return Stack(
      alignment: Alignment.center,
      children: [
        if (value > 0.3)
          Container(
            width: widget.size * (1.3 + value * 0.5),
            height: widget.size * (1.3 + value * 0.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: (value - 0.3) * 0.4),
            ),
          ),
        Transform.scale(
          scale: scale,
          child: Icon(Icons.star, size: widget.size, color: color),
        ),
      ],
    );
  }
}
