import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/entry/zone_selection_screen.dart';
import 'package:safezone/screens/home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _logoFadeAnim;
  late Animation<double> _logoScaleAnim;
  late Animation<double> _textFadeAnim;
  late Animation<double> _descFadeAnim;
  late Animation<double> _tipsFadeAnim;
  late Animation<double> _loadingFadeAnim;

  late final String _randomTip;

  Timer? _navTimer;

  // 5 consejos de seguridad vecinal
  static const List<String> _safetyTips = [
    '🔐 Mantén puertas y ventanas cerradas, incluso de día.',
    '📱 Guarda los números de emergencia: Policía 105, SAMU 106, Bomberos 116.',
    '👥 Conoce a tus vecinos. Una comunidad unida es más segura.',
    '💡 Reporta focos de alumbrado público malogrados en SafeZone.',
    '🚶 Comparte tu ubicación con "Camina Conmigo" al salir de noche.',
  ];

  @override
  void initState() {
    super.initState();

    _randomTip = _safetyTips[Random().nextInt(_safetyTips.length)];

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _logoFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _logoScaleAnim = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
      ),
    );

    _textFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.2, 0.55, curve: Curves.easeIn),
      ),
    );

    _descFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.65, curve: Curves.easeIn),
      ),
    );

    _tipsFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.5, 0.85, curve: Curves.easeIn),
      ),
    );

    _loadingFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.6, 0.9, curve: Curves.easeIn),
      ),
    );

    _animController.forward();

    // Esperar 4 segundos antes de navegar
    _navTimer = Timer(const Duration(seconds: 4), () async {
      if (!mounted) return;

      // Verificar si ya existe un código de dispositivo guardado
      final prefs = await SharedPreferences.getInstance();
      
      if (!mounted) return;
      
      final existingCode = prefs.getString('user_device_code');
      final existingZone = prefs.getInt('user_zone');

      if (existingCode != null && existingZone != null) {
        // Código existente → ir directamente al HomeScreen
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              userCode: existingCode,
              zone: existingZone,
            ),
          ),
        );
      } else {
        // Primera vez → ir a la selección de zona
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ZoneSelectionScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.brandRedDark,
              AppTheme.brandRedBright,
              Color(0xFF8B0000),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // Elementos decorativos de fondo
            Positioned(
              top: -100, right: -100,
              child: Container(
                width: 320, height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              bottom: -80, left: -80,
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.35, right: -30,
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ),
            Positioned(
              top: 120, left: -40,
              child: Transform.rotate(
                angle: -0.3,
                child: Container(
                  width: 200, height: 1.5,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 200, right: -30,
              child: Transform.rotate(
                angle: 0.5,
                child: Container(
                  width: 150, height: 1.5,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),

            // Contenido principal
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // Logo animado
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _logoFadeAnim.value,
                        child: Transform.scale(
                          scale: _logoScaleAnim.value,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: 200, height: 200,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Image.asset(
                        'assets/icons/logo-app.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.shield, size: 80, color: Colors.white);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Título
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _textFadeAnim.value,
                        child: child,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        children: [
                          const Text(
                            'SafeZone',
                            style: TextStyle(
                              fontSize: 38, fontWeight: FontWeight.bold,
                              color: Colors.white, letterSpacing: 4,
                              shadows: [Shadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Red vecinal de seguridad',
                            style: TextStyle(
                              fontSize: 17, color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 2, fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Collique, Comas',
                            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 1),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Descripción corta debajo del logo
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _descFadeAnim.value,
                        child: child,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.white.withValues(alpha: 0.1),
                            Colors.white.withValues(alpha: 0.05),
                          ]),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Text(
                          'Red vecinal para reportes de seguridad, alertas S.O.S. y colaboración comunitaria en tiempo real.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8), height: 1.5, letterSpacing: 0.3),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Consejo aleatorio en la parte inferior
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _tipsFadeAnim.value,
                        child: child,
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _randomTip,
                              style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Loading
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _loadingFadeAnim.value,
                        child: child,
                      );
                    },
                    child: _LoadingDots(),
                  ),

                  const SizedBox(height: 16),

                  // Versión
                  Text(
                    'v1.0.0',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.25), letterSpacing: 1.5),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final dotValue = ((_dotsController.value - delay) % 1.0).clamp(0.0, 1.0);
            final scale = 0.6 + (0.4 * (1 - (dotValue * 2 - 1).abs()));
            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
