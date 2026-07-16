import 'dart:math';
import 'package:flutter/material.dart';

/// Overlay de confeti animado con partículas de colores que caen.
/// Se usa para celebrar subidas de nivel, logros, etc.
class ConfettiOverlay extends StatefulWidget {
  final int particleCount;
  final List<Color> colors;
  final Duration duration;
  final VoidCallback? onComplete;
  final bool playSound;

  const ConfettiOverlay({
    super.key,
    this.particleCount = 60,
    this.colors = const [
      Color(0xFFFF1744), // Rojo
      Color(0xFFFFD600), // Amarillo
      Color(0xFF00E676), // Verde
      Color(0xFF2979FF), // Azul
      Color(0xFFD500F9), // Púrpura
      Color(0xFFFF9100), // Naranja
      Color(0xFF00BCD4), // Cian
    ],
    this.duration = const Duration(milliseconds: 2500),
    this.onComplete,
    this.playSound = true,
  });

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<_ConfettiParticle> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _particles = List.generate(widget.particleCount, (_) {
      return _ConfettiParticle(
        x: _random.nextDouble(),
        y: -0.1 - _random.nextDouble() * 0.3,
        speedX: (_random.nextDouble() - 0.5) * 0.4,
        speedY: 0.3 + _random.nextDouble() * 0.5,
        rotation: _random.nextDouble() * 2 * pi,
        rotationSpeed: (_random.nextDouble() - 0.5) * 4,
        size: 4 + _random.nextDouble() * 8,
        color: widget.colors[_random.nextInt(widget.colors.length)],
        wobble: _random.nextDouble() * 2 * pi,
        wobbleSpeed: 1 + _random.nextDouble() * 2,
        wobbleAmount: 0.02 + _random.nextDouble() * 0.04,
        shape: _random.nextInt(3),
      );
    });

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            progress: _controller.value,
            particles: _particles,
          ),
        );
      },
    );
  }
}

/// Partícula individual de confeti
class _ConfettiParticle {
  double x;
  double y;
  double speedX;
  double speedY;
  double rotation;
  double rotationSpeed;
  double size;
  Color color;
  double wobble;
  double wobbleSpeed;
  double wobbleAmount;
  int shape; // 0=circle, 1=square, 2=line

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.speedX,
    required this.speedY,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
    required this.color,
    required this.wobble,
    required this.wobbleSpeed,
    required this.wobbleAmount,
    required this.shape,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiParticle> particles;

  _ConfettiPainter({required this.progress, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final t = progress;

      // Calcular posición
      final x = (particle.x + particle.speedX * t + 
                 sin(particle.wobble + t * particle.wobbleSpeed) * particle.wobbleAmount) * size.width;
      final y = (particle.y + particle.speedY * t) * size.height;

      // Si ya salió de la pantalla, skip
      if (y > size.height + 20) continue;

      final rotation = particle.rotation + particle.rotationSpeed * t;
      final alpha = t < 0.8 ? 1.0 : (1.0 - (t - 0.8) / 0.2);
      final currentSize = particle.size * (1.0 - t * 0.3);

      if (currentSize < 1) continue;

      final paint = Paint()
        ..color = particle.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill
        ..strokeWidth = currentSize * 0.6;

      final center = Offset(x, y);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);

      switch (particle.shape) {
        case 0: // Círculo
          canvas.drawCircle(Offset.zero, currentSize / 2, paint);
          break;
        case 1:          // Cuadrado
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: currentSize, height: currentSize),
              const Radius.circular(2),
            ),
            paint,
          );
          break;
        case 2: // Línea / rectángulo alargado
          canvas.drawLine(
            Offset(-currentSize / 2, 0),
            Offset(currentSize / 2, 0),
            paint,
          );
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Variante minimalista: solo muestra unas pocas estrellas brillantes
class StarBurstOverlay extends StatefulWidget {
  final VoidCallback? onComplete;

  const StarBurstOverlay({super.key, this.onComplete});

  @override
  State<StarBurstOverlay> createState() => _StarBurstOverlayState();
}

class _StarBurstOverlayState extends State<StarBurstOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward().then((_) => widget.onComplete?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _StarBurstPainter(progress: _controller.value),
        );
      },
    );
  }
}

class _StarBurstPainter extends CustomPainter {
  final double progress;

  _StarBurstPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final burstRadius = size.width * 0.7;
    final starCount = 12;

    for (int i = 0; i < starCount; i++) {
      final angle = (i / starCount) * 2 * pi + progress * pi * 0.5;
      final distance = burstRadius * progress;
      final x = center.dx + distance * cos(angle);
      final y = center.dy + distance * sin(angle);
      final alpha = progress < 0.6 ? 1.0 : (1.0 - (progress - 0.6) / 0.4);
      final starSize = 2.0 + progress * 6.0;

      final paint = Paint()
        ..color = Colors.amber.withValues(alpha: alpha * 0.8)
        ..style = PaintingStyle.fill;

      // Dibujar estrella de 4 puntas
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);

      final path = Path();
      path.moveTo(0, -starSize);
      path.lineTo(starSize * 0.3, -starSize * 0.3);
      path.lineTo(starSize, 0);
      path.lineTo(starSize * 0.3, starSize * 0.3);
      path.lineTo(0, starSize);
      path.lineTo(-starSize * 0.3, starSize * 0.3);
      path.lineTo(-starSize, 0);
      path.lineTo(-starSize * 0.3, -starSize * 0.3);
      path.close();

      canvas.drawPath(path, paint);
      canvas.restore();
    }

    // Centro brillante
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: progress < 0.5 ? progress * 2 : (1.0 - progress) * 2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4 + progress * 6, centerPaint);
  }

  @override
  bool shouldRepaint(_StarBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
