import 'dart:math' as math;
import 'package:flutter/material.dart';

// ============================================================
// REACTION PARTICLES OVERLAY
// ============================================================
// Muestra una explosión de partículas coloridas cuando el
// usuario reacciona con un emoji en el Muro.
// ============================================================

/// Muestra una lluvia de partículas animadas en la posición dada.
/// Retorna el OverlayEntry para poder removerlo después.
OverlayEntry showReactionParticles(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ReactionParticlesOverlay(
      position: globalPosition,
      onComplete: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
  return entry;
}

class _ReactionParticlesOverlay extends StatefulWidget {
  final Offset position;
  final VoidCallback onComplete;

  const _ReactionParticlesOverlay({
    required this.position,
    required this.onComplete,
  });

  @override
  State<_ReactionParticlesOverlay> createState() =>
      _ReactionParticlesOverlayState();
}

class _ReactionParticlesOverlayState extends State<_ReactionParticlesOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// Genera 12 partículas con datos aleatorios
  final List<_ParticleData> _particles = List.generate(12, (i) {
    final angle = (i / 12) * math.pi * 2 + (math.Random().nextDouble() - 0.5) * 0.5;
    final speed = 80.0 + math.Random().nextDouble() * 120;
    return _ParticleData(
      dx: math.cos(angle) * speed,
      dy: math.sin(angle) * speed,
      color: [
        const Color(0xFFC3110C),
        const Color(0xFFFFA000),
        const Color(0xFF388E3C),
        const Color(0xFF1976D2),
        const Color(0xFF7B1FA2),
        const Color(0xFFFF6F00),
      ][i % 6],
      size: 4.0 + math.Random().nextDouble() * 6,
      delay: math.Random().nextDouble() * 0.1,
    );
  });

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete();
        }
      });
    _controller.forward();
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
        final progress = _controller.value;
        return IgnorePointer(
          child: Stack(
            children: _particles.map((p) {
              final pProgress = ((progress - p.delay) / (1 - p.delay))
                  .clamp(0.0, 1.0);
              final eased = Curves.easeOutCubic.transform(pProgress);
              final opacity = (1 - eased) * 0.9;
              final scale = 1.0 + eased * 0.5;

              return Positioned(
                left: widget.position.dx + p.dx * eased - p.size / 2,
                top: widget.position.dy + p.dy * eased - p.size / 2,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: p.size,
                      height: p.size,
                      decoration: BoxDecoration(
                        color: p.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: p.color.withValues(alpha: 0.4),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _ParticleData {
  final double dx;
  final double dy;
  final Color color;
  final double size;
  final double delay;

  const _ParticleData({
    required this.dx,
    required this.dy,
    required this.color,
    required this.size,
    required this.delay,
  });
}
