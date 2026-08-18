import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// APP TUTORIAL — Onboarding interactivo y visual
// ============================================================
// Tutorial de 7 pasos con animaciones, iconos brillantes,
// gradientes y elementos visuales llamativos.
//
// Se muestra solo la PRIMERA VEZ que el usuario entra a HomeScreen.
// ============================================================

/// Datos de cada paso del tutorial
class _TutorialStep {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color1;
  final Color color2;
  final String emoji;

  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color1,
    required this.color2,
    this.emoji = '🛡️',
  });
}

/// Las 7 estaciones del tutorial
const List<_TutorialStep> _steps = [
  _TutorialStep(
    icon: Icons.shield_rounded,
    title: '¡Bienvenido, Guardián!',
    subtitle:
        'Has entrado a SafeZone, la red vecinal que protege Collique. Descubre cómo puedes ayudar a tu comunidad.',
    color1: Color(0xFFC3110C),
    color2: Color(0xFF740A03),
    emoji: '🦸',
  ),
  _TutorialStep(
    icon: Icons.newspaper,
    title: 'Muro Vecinal',
    subtitle:
        'Aquí ves todos los reportes de tus vecinos en tiempo real. Puedes reaccionar con 🛡️⚠️ y comentar para apoyar.',
    color1: Color(0xFF1565C0),
    color2: Color(0xFF0D47A1),
    emoji: '📰',
  ),
  _TutorialStep(
    icon: Icons.map,
    title: 'Mapa de Riesgo',
    subtitle:
        'Visualiza incidentes cerca de ti. Los colores te indican el tipo: 🔴 Robo, 🟠 Sospechoso, 🟡 Alumbrado.',
    color1: Color(0xFF2E7D32),
    color2: Color(0xFF1B5E20),
    emoji: '🗺️',
  ),
  _TutorialStep(
    icon: Icons.sos,
    title: 'Alerta S.O.S.',
    subtitle:
        '¿Emergencia? Activa el botón rojo. Comparte una ubicación aproximada durante 60 segundos con vecinos conectados.',
    color1: Color(0xFFD32F2F),
    color2: Color(0xFFB71C1C),
    emoji: '🚨',
  ),
  _TutorialStep(
    icon: Icons.add_circle,
    title: 'Reporta con Evidencia',
    subtitle:
        'Toma foto o video de cualquier incidente. Elige categoría y nivel de gravedad para mantener informada a la comunidad.',
    color1: Color(0xFFE65100),
    color2: Color(0xFFBF360C),
    emoji: '📸',
  ),
  _TutorialStep(
    icon: Icons.chat,
    title: 'Chat Vecinal',
    subtitle:
        'Conversa con tus vecinos de forma anónima. Coordina rondas, comparte información y fortalece la comunidad.',
    color1: Color(0xFF7B1FA2),
    color2: Color(0xFF4A148C),
    emoji: '💬',
  ),
  _TutorialStep(
    icon: Icons.shield_rounded,
    title: '¡Zona Segura Activada!',
    subtitle:
        'Recuerda: ZoneBot siempre está disponible. Solo toca el globo flotante para hablar con tu asistente IA.',
    color1: AppTheme.primaryGreen,
    color2: AppTheme.brandRedBright,
    emoji: '🎉',
  ),
];

/// Tutorial interactivo de la app
class AppTutorial extends StatefulWidget {
  /// Called when the user finishes or skips the tutorial
  final VoidCallback onComplete;

  final String userCode;
  final int zone;

  const AppTutorial({
    super.key,
    required this.onComplete,
    required this.userCode,
    required this.zone,
  });

  /// Verifica si es la primera vez del usuario
  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final tutorialDone = prefs.getBool('tutorial_completed') ?? false;
    return !tutorialDone;
  }

  /// Marca el tutorial como completado
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_completed', true);
  }

  @override
  State<AppTutorial> createState() => _AppTutorialState();
}

class _AppTutorialState extends State<AppTutorial>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  late Animation<double> _slideAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  void _nextStep() {
    HapticFeedback.lightImpact();
    SoundService().play('nav_tap');

    if (_currentStep >= _steps.length - 1) {
      _finishTutorial();
      return;
    }

    _slideController.reverse().then((_) {
      if (!mounted) return;
      setState(() => _currentStep++);
      _slideController.forward();
    });
  }

  void _finishTutorial() async {
    await AppTutorial.markCompleted();
    SoundService().play('zonebot_open');
    widget.onComplete();
  }

  void _skipTutorial() {
    HapticFeedback.mediumImpact();
    _finishTutorial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _steps[_currentStep].color1,
              _steps[_currentStep].color2,
              const Color(0xFF1A1A2E),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // === Fondo decorativo con partículas animadas ===
            AnimatedBuilder(
              animation: _particleController,
              builder: (context, child) {
                final progress = _particleController.value;
                return CustomPaint(
                  painter: _TutorialParticlePainter(
                    progress: progress,
                    color: Colors.white,
                  ),
                  size: Size.infinite,
                );
              },
            ),

            // === Contenido principal ===
            SafeArea(
              child: Column(
                children: [
                  // === Top bar: Skip + Progress ===
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        // Botón Skip
                        GestureDetector(
                          onTap: _skipTutorial,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Saltar ${_steps.length - _currentStep - 1 > 0 ? '(${_steps.length - _currentStep - 1})' : ''}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Indicador de pasos (estilo brillante)
                        ...List.generate(_steps.length, (i) {
                          final isActive = i == _currentStep;
                          final isPast = i < _currentStep;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: isActive ? 24 : 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: isActive
                                  ? Colors.white
                                  : isPast
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.2),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: Colors.white.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // === Contenido animado del paso actual ===
                  AnimatedBuilder(
                    animation: _slideAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _slideAnimation.value,
                        child: Transform.translate(
                          offset: Offset(0, 30 * (1 - _slideAnimation.value)),
                          child: _buildStepContent(),
                        ),
                      );
                    },
                  ),

                  const Spacer(flex: 2),

                  // === Botón Continuar ===
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: ElevatedButton(
                              onPressed: _nextStep,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: _steps[_currentStep].color1,
                                disabledBackgroundColor: Colors.white30,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 8,
                                shadowColor: Colors.white.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _currentStep >= _steps.length - 1
                                        ? '¡COMENZAR!'
                                        : 'CONTINUAR',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  if (_currentStep < _steps.length - 1) ...[
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 20,
                                    ),
                                  ] else ...[
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.celebration_outlined,
                                      size: 20,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construye el contenido visual del paso actual
  Widget _buildStepContent() {
    final step = _steps[_currentStep];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // === Icono grande con brillo ===
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.1),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Brillo rotatorio de fondo
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 100 + _pulseController.value * 20,
                      height: 100 + _pulseController.value * 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.15),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // Icono grande
                Icon(step.icon, size: 56, color: Colors.white),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // === Emoji decorativo flotante ===
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  0,
                  -4 * math.sin(_pulseController.value * math.pi * 2),
                ),
                child: Text(step.emoji, style: const TextStyle(fontSize: 36)),
              );
            },
          ),

          const SizedBox(height: 12),

          // === Título ===
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1,
              shadows: [
                Shadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // === Subtítulo ===
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Text(
              step.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.88),
                height: 1.5,
                letterSpacing: 0.3,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // === Indicador visual del paso (número) ===
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Paso ${_currentStep + 1} de ${_steps.length}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PAINTER: Partículas decorativas de fondo
// ============================================================
class _TutorialParticlePainter extends CustomPainter {
  final double progress;
  final Color color;

  _TutorialParticlePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    // 8 círculos decorativos que flotan lentamente
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * math.pi * 2 + progress * math.pi * 0.3;
      final radius =
          size.width * 0.35 +
          math.sin(progress * math.pi * 2 + i) * size.width * 0.05;
      final cx = size.width / 2 + math.cos(angle) * radius;
      final cy = size.height / 2 + math.sin(angle) * radius * 0.6;
      final circleSize =
          20 + math.sin(progress * math.pi * 3 + i * 0.7) * 15 + 15;

      canvas.drawCircle(Offset(cx, cy), circleSize, paint);
    }
  }

  @override
  bool shouldRepaint(_TutorialParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
