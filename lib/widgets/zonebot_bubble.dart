import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';

// ============================================================
// ZONEBOT FLOATING BUBBLE — ASSISTANT FLOATING BUTTON
// ============================================================
// Globo flotante que abre el chat de ZoneBot. Se muestra en todas
// las pantallas.
//
// Características:
//   - Entrada suave (fade + escala ligera, sin rebote elástico)
//   - Sin animaciones continuas (estático después de aparecer)
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
  // Animación de entrada única (fade + escala ligera)
  late AnimationController _entranceController;
  late Animation<double> _entranceScale;
  late Animation<double> _entranceOpacity;

  /// Trackea si el usuario está arrastrando (para no confundir con tap)
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _entranceScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );

    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOut,
      ),
    );

    // Iniciar animación de entrada después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
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
        return Opacity(
          opacity: _entranceOpacity.value,
          child: Transform.scale(
            scale: _entranceScale.value,
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
                      color: AppTheme.primaryGreen.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
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
