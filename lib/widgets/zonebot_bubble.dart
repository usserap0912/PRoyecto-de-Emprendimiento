import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

// ============================================================
// ZONEBOT FLOATING BUBBLE — ASSISTANT FLOATING BUTTON
// ============================================================
// Globo flotante animado que abre el chat de ZoneBot como
// asistente de la app. Se muestra en todas las pantallas.
//
// Características:
//   - Entrada con animación bounce (escala elástica)
//   - Pulsación suave continua (respiración)
//   - Arrastrable a cualquier posición de la pantalla
//   - Indicador verde "En línea"
// ============================================================

/// Callback for drag movement
typedef BubbleDragCallback = void Function(Offset delta);

class ZoneBotBubble extends StatefulWidget {
  /// Called when the bubble is tapped
  final VoidCallback onTap;

  /// Called when the user drags the bubble
  final BubbleDragCallback? onDragUpdate;

  /// Called when the user finishes dragging
  final VoidCallback? onDragEnd;

  const ZoneBotBubble({
    super.key,
    required this.onTap,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  State<ZoneBotBubble> createState() => _ZoneBotBubbleState();
}

class _ZoneBotBubbleState extends State<ZoneBotBubble>
    with SingleTickerProviderStateMixin {
  // ================================================================
  // ANIMACIONES
  // ================================================================
  // _entranceController: Animación de entrada (bounce + fade in)
  // _pulseController:    Animación continua de respiración
  // ================================================================

  late AnimationController _entranceController;
  late AnimationController _pulseController;

  late Animation<double> _entranceScale;
  late Animation<double> _entranceOpacity;

  bool _entranceDone = false;

  /// Trackea si el usuario está arrastrando (para no confundir con tap)
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();

    // --- Controlador de entrada (bounce) ---
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _entranceScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.elasticOut,
      ),
    );

    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
      ),
    );

    // --- Controlador de pulsación continua ---
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Iniciar animación de entrada después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceController.forward().then((_) {
        if (mounted) {
          _pulseController.repeat(reverse: true);
          setState(() => _entranceDone = true);
        }
      });
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ================================================================
  // GESTOS: Arrastre
  // ================================================================

  void _onPanStart(DragStartDetails details) {
    _isDragging = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _isDragging = true;
    widget.onDragUpdate?.call(details.delta);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDragging) {
      widget.onDragEnd?.call();
    }
  }

  void _onTapUp(TapUpDetails details) {
    // Solo abrir si no hubo arrastre
    if (!_isDragging) {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        // Escala combinada: entrada × pulsación
        final entranceScale = _entranceScale.value;
        final entranceOpacity = _entranceOpacity.value;

        final pulse = _pulseController.value;
        final breatheScale = 1.0 + (pulse * 0.04);

        return Opacity(
          opacity: entranceOpacity,
          child: Transform.scale(
            scale: entranceScale * breatheScale,
            child: GestureDetector(
              onTapUp: _onTapUp,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Container(
                width: 60,
                height: 60,
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
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGreen
                          .withValues(alpha: 0.3 + pulse * 0.2),
                      blurRadius: 8 + pulse * 6,
                      spreadRadius: 1 + pulse * 2,
                    ),
                    BoxShadow(
                      color: AppTheme.brandRedBright.withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: Stack(
                  children: [
                    // Escudo principal
                    const Center(
                      child: Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),

                    // Anillo pulsante (solo después de la entrada)
                    if (_entranceDone)
                      CustomPaint(
                        painter: _BubbleRingPainter(
                          progress: pulse,
                        ),
                        size: const Size(60, 60),
                      ),

                    // Indicador "En línea"
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : Colors.white,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.greenAccent.withValues(alpha: 0.6),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Tooltip pequeño al hacer drag
                    if (_isDragging)
                      Positioned(
                        bottom: -2,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Arrastra',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints a subtle pulsing ring around the bubble
class _BubbleRingPainter extends CustomPainter {
  final double progress;

  _BubbleRingPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1 + progress * 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + progress;

    canvas.drawCircle(center, radius - progress * 2, ringPaint);
  }

  @override
  bool shouldRepaint(_BubbleRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
