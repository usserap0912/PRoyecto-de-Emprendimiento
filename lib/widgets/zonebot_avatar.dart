import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

// ============================================================
// ZONEBOT AVATAR WIDGET
// ============================================================
// Widget animado que muestra el avatar de ZoneBot con 3 estados:
//   'idle'     → Respiración suave con escudo pulsante
//   'thinking' → Círculo de carga girando alrededor del escudo
//   'happy'    → Escudo brillante con efecto de celebración
//
// TODO: Reemplazar el CustomPainter con RiveAnimation cuando
//       el archivo .riv esté listo. Ver ejemplo abajo.
// ============================================================

/// Controlador de animación para ZoneBot.
///
/// Maneja el estado actual y las transiciones suaves entre estados.
class ZoneBotAvatar extends StatefulWidget {
  /// Estado actual de la animación: 'idle', 'thinking', o 'happy'
  final String state;

  /// Tamaño del avatar (ancho y alto)
  final double size;

  const ZoneBotAvatar({
    super.key,
    required this.state,
    this.size = 80,
  });

  @override
  State<ZoneBotAvatar> createState() => _ZoneBotAvatarState();
}

class _ZoneBotAvatarState extends State<ZoneBotAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void didUpdateWidget(ZoneBotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _controller.reset();
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [
                AppTheme.primaryGreen,
                AppTheme.brandRedBright,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: _buildShadow(progress, isDark),
          ),
          child: CustomPaint(
            painter: _ZoneBotPainter(
              state: widget.state,
              progress: progress,
              isDark: isDark,
            ),
            child: Center(
              child: _buildInnerContent(progress),
            ),
          ),
        );
      },
    );
  }

  /// Sombra dinámica según el estado de animación
  List<BoxShadow> _buildShadow(double progress, bool isDark) {
    switch (widget.state) {
      case 'thinking':
        // Sombra naranja pulsante
        final pulse = (math.sin(progress * math.pi * 4) + 1) / 2;
        return [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3 + pulse * 0.3),
            blurRadius: 12 + pulse * 10,
            spreadRadius: 1 + pulse * 2,
          ),
        ];
      case 'happy':
        // Sombra verde brillante con destello
        final flash = (math.sin(progress * math.pi * 3) + 1) / 2;
        return [
          BoxShadow(
            color: Colors.greenAccent.withValues(alpha: 0.2 + flash * 0.4),
            blurRadius: 15,
            spreadRadius: 2 + flash * 3,
          ),
        ];
      default: // idle
        // Sombra suave y constante
        final breathe = (math.sin(progress * math.pi * 2) + 1) / 2;
        return [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1 + breathe * 0.1),
            blurRadius: 8 + breathe * 4,
            spreadRadius: breathe * 1,
          ),
        ];
    }
  }

  /// Contenido interior del avatar según el estado
  Widget? _buildInnerContent(double progress) {
    if (widget.state == 'thinking') {
      return SizedBox(
        width: widget.size * 0.4,
        height: widget.size * 0.4,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(
            HSLColor.fromColor(Colors.white)
                .withLightness(0.8 + math.sin(progress * math.pi * 2) * 0.2)
                .toColor(),
          ),
        ),
      );
    }
    return Icon(
      widget.state == 'happy' ? Icons.shield : Icons.shield_rounded,
      size: widget.size * 0.5,
      color: Colors.white,
    );
  }
}

// ============================================================
// CUSTOM PAINTER: Efectos visuales según el estado
// ============================================================

class _ZoneBotPainter extends CustomPainter {
  final String state;
  final double progress;
  final bool isDark;

  _ZoneBotPainter({
    required this.state,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    switch (state) {
      case 'thinking':
        _paintThinkingRing(canvas, center, radius);
        break;
      case 'happy':
        _paintHappySparkles(canvas, center, radius);
        break;
      default: // idle
        _paintIdlePulse(canvas, center, radius);
        break;
    }
  }

  /// Efecto idle: anillo pulsante alrededor del escudo
  void _paintIdlePulse(Canvas canvas, Offset center, double radius) {
    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1 + pulse * 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + pulse;
    canvas.drawCircle(center, radius - 3 - pulse * 2, paint);
  }

  /// Efecto thinking: anillos de carga giratorios
  void _paintThinkingRing(Canvas canvas, Offset center, double radius) {
    final rotation = progress * math.pi * 2;
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Anillo principal
    canvas.drawCircle(center, radius - 4, ringPaint);

    // Arco giratorio (como loading)
    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      rotation,
      math.pi * 1.3,
      false,
      arcPaint,
    );
  }

  /// Efecto happy: destellos alrededor del escudo
  void _paintHappySparkles(Canvas canvas, Offset center, double radius) {
    final sparkPaint = Paint()
      ..color = Colors.yellowAccent.withValues(alpha: 0.6 + math.sin(progress * math.pi * 4) * 0.3)
      ..style = PaintingStyle.fill;

    // Rayos de estrella girando
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * math.pi * 2 + progress * math.pi * 0.5;
      final sparkRadius = radius - 6 + math.sin(progress * math.pi * 2 + i) * 4;
      final x = center.dx + math.cos(angle) * sparkRadius;
      final y = center.dy + math.sin(angle) * sparkRadius;
      canvas.drawCircle(Offset(x, y), 1.5 + math.sin(progress * math.pi * 2 + i * 0.5) * 1, sparkPaint);
    }

    // Brillo pulsante
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05 + math.sin(progress * math.pi * 2) * 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 2, glowPaint);
  }

  @override
  bool shouldRepaint(_ZoneBotPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark;
  }
}

// ============================================================
// IMPLEMENTACIÓN CON RIVE (CUANDO EL .riv ESTÉ LISTO)
// ============================================================
// Reemplazar el contenido de ZoneBotAvatar con:
//
// ```dart
// import 'package:rive/rive.dart' as rive;
//
// class ZoneBotAvatar extends StatefulWidget {
//   final String state;
//   final double size;
//
//   const ZoneBotAvatar({super.key, required this.state, this.size = 80});
//
//   @override
//   State<ZoneBotAvatar> createState() => _ZoneBotAvatarState();
// }
//
// class _ZoneBotAvatarState extends State<ZoneBotAvatar> {
//   rive.StateMachineController? _riveController;
//   late final rive.RiveAnimation _animation;
//
//   @override
//   void initState() {
//     super.initState();
//     _animation = rive.RiveAnimation.asset(
//       'assets/animations/zonebot.riv',
//       artboard: 'ZoneBot',
//       stateMachines: ['State'],
//       onInit: (artboard) {
//         _riveController = rive.StateMachineController.fromArtboard(
//           artboard, 'State',
//         );
//         if (_riveController != null) {
//           artboard.addController(_riveController!);
//           _triggerState(widget.state);
//         }
//       },
//     );
//   }
//
//   @override
//   void didUpdateWidget(ZoneBotAvatar oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (oldWidget.state != widget.state) {
//       _triggerState(widget.state);
//     }
//   }
//
//   void _triggerState(String state) {
//     // Los nombres de los triggers deben coincidir con los definidos
//     // en el StateMachine de Rive
//     switch (state) {
//       case 'thinking':
//         _riveController?.fire('thinking');
//         break;
//       case 'happy':
//         _riveController?.fire('happy');
//         break;
//       default:
//         _riveController?.fire('idle');
//         break;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return SizedBox(
//       width: widget.size,
//       height: widget.size,
//       child: _animation,
//     );
//   }
// }
// ```
