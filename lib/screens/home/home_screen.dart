import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/wall/wall_screen.dart';
import 'package:safezone/screens/map/risk_map_screen.dart';
import 'package:safezone/screens/sos/sos_screen.dart';
import 'package:safezone/screens/chat/community_chat_screen.dart';
import 'package:safezone/screens/chat/zonebot_screen.dart';
import 'package:safezone/screens/report/report_form_screen.dart';
import 'package:safezone/screens/premium/premium_screen.dart';
import 'package:safezone/widgets/zonebot_bubble.dart';
import 'package:safezone/widgets/app_tutorial.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/notification_service.dart';
import 'package:safezone/services/zonebot_service.dart';
import 'package:safezone/services/report_service.dart';
import 'package:safezone/widgets/animated_nav_icon.dart';
import 'package:safezone/models/sos_alert.dart';
import 'package:safezone/services/sos_realtime_service.dart';
import 'package:shimmer/shimmer.dart';

class HomeScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const HomeScreen({super.key, required this.userCode, required this.zone});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final SoundService _soundService = SoundService();
  final SupabaseService _supabaseService = SupabaseService();
  final NotificationService _notificationService = NotificationService();
  final SosRealtimeService _sosRealtimeService = SosRealtimeService();
  Timer? _incomingSosTimer;
  SosAlert? _incomingSosAlert;

  // ================================================================
  // CREDIT WARNING: Banner animado cuando hay pocos créditos
  // ================================================================
  late AnimationController _creditWarningController;
  bool _creditWarningVisible = false;
  bool _creditWarningDismissed = false;

  // ================================================================
  // CREDIT BANNER TUTORIAL: Overlay animado primera vez
  // ================================================================
  static const String _prefsCreditTutorialSeen = 'credit_tutorial_seen';
  late AnimationController _tutorialHandController;
  bool _showCreditTutorial = false;

  late final List<Widget> _screens;

  // ================================================================
  // GLOBO FLOTANTE: Posición arrastrable + persistente
  // ================================================================
  double _bubbleLeft = 0;
  double _bubbleTop = 0;
  bool _bubbleReady = false;
  bool _bubbleLoaded = false;

  static const String _prefsBubbleLeft = 'zonebot_bubble_left';
  static const String _prefsBubbleTop = 'zonebot_bubble_top';

  /// Carga la posición guardada del globo desde SharedPreferences
  Future<void> _loadBubblePosition(Size screenSize) async {
    if (_bubbleLoaded) return;
    _bubbleLoaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final savedLeft = prefs.getDouble(_prefsBubbleLeft);
      final savedTop = prefs.getDouble(_prefsBubbleTop);

      if (savedLeft != null && savedTop != null) {
        setState(() {
          _bubbleLeft = savedLeft;
          _bubbleTop = savedTop;
          _bubbleReady = true;
        });
        return;
      }
    } catch (e) {
      debugPrint('HomeScreen: Error cargando posición del globo: $e');
    }
    if (!mounted) return;

    // Posición por defecto: esquina inferior derecha
    setState(() {
      _bubbleLeft = screenSize.width - 60 - 16;
      _bubbleTop = screenSize.height - 60 - 80;
      _bubbleReady = true;
    });
  }

  /// Guarda la posición del globo en SharedPreferences
  Future<void> _saveBubblePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsBubbleLeft, _bubbleLeft);
      await prefs.setDouble(_prefsBubbleTop, _bubbleTop);
    } catch (e) {
      debugPrint('HomeScreen: Error guardando posición del globo: $e');
    }
  }

  // ================================================================
  // ANIMACIÓN DE ENTRADA (Welcome)
  // ================================================================
  late AnimationController _welcomeController;
  late Animation<double> _welcomeOpacity;
  bool _showWelcome = true;

  // ================================================================
  // INICIALIZACIÓN
  // ================================================================
  @override
  void initState() {
    super.initState();

    // Inicializar sonido y notificaciones
    _soundService.initialize();
    _notificationService.initialize();
    _sosRealtimeService.incomingAlert.addListener(_onIncomingSosAlert);
    _sosRealtimeService.start(currentUserCode: widget.userCode);

    _screens = [
      WallScreen(userCode: widget.userCode, zone: widget.zone),
      RiskMapScreen(userCode: widget.userCode),
      SosScreen(userCode: widget.userCode, zone: widget.zone),
      CommunityChatScreen(userCode: widget.userCode),
      ReportFormScreen(userCode: widget.userCode, zone: widget.zone),
      PremiumScreen(
        userCode: widget.userCode,
        zone: widget.zone,
        onPremiumChanged: () {
          if (mounted) setState(() {});
        },
      ),
    ];

    // Animación de bienvenida
    _welcomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _welcomeOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _welcomeController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );

    // Inicializar todo después del primer frame (una sola vez)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Posición del globo
      _loadBubblePosition(MediaQuery.of(context).size);

      // Sonido de bienvenida
      _soundService.play('welcome');
      _welcomeController.forward().then((_) {
        if (mounted) {
          setState(() => _showWelcome = false);
          // Mostrar tutorial interactivo TRAS la animación de bienvenida
          _checkAndShowTutorial();
        }
      });
    });

    // Animación del banner de créditos
    _creditWarningController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Animación del tutorial (mano señalando) — estática, sin rebote
    _tutorialHandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Verificar créditos después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCredits();
    });

    // Archivar reportes antiguos al iniciar (solo una vez)
    _archiveOldReportsOnce();

    // Notificación semanal de ranking (tras primer frame para que NotificationService esté listo)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkWeeklyRanking();
    });

    // Suscribirse a notificaciones de robos en tiempo real
    _subscribeToRoboNotifications();
  }

  /// Verifica si es primera vez y muestra el tutorial interactivo
  Future<void> _checkAndShowTutorial() async {
    final isFirstLaunch = await AppTutorial.isFirstLaunch();
    if (isFirstLaunch && mounted) {
      SoundService().play('zonebot_open');
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black,
        builder: (_) => PopScope(
          canPop: false,
          child: AppTutorial(
            userCode: widget.userCode,
            zone: widget.zone,
            onComplete: () => Navigator.of(context).pop(true),
          ),
        ),
      );
      if (result == true && mounted) {
        SoundService().play('happy');
      }
    }
  }

  /// Escucha reportes de robo y muestra notificaciones locales
  void _subscribeToRoboNotifications() {
    _supabaseService.subscribeToRoboNotifications(
      onRoboDetected: (data) {
        _notificationService.showRoboAlert(
          zone: data.zone,
          timeAgo: data.timeAgo,
          distance: data.distance,
          similarReports: data.similarReportsCount,
        );
      },
    );
  }

  /// Verifica el ranking semanal y muestra notificación si cambió la semana.
  Future<void> _checkWeeklyRanking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastWeekNotif = prefs.getInt('last_ranking_week') ?? 0;
      final currentWeek = _getIsoWeek(DateTime.now());

      if (currentWeek == lastWeekNotif) return;

      final ranking = await _supabaseService.getRanking(limit: 50);
      if (!mounted) return;

      final myIndex = ranking.indexWhere(
        (r) => r['user_code'] == widget.userCode,
      );

      if (myIndex >= 0) {
        final position = myIndex + 1;
        final totalPoints = ranking[myIndex]['total_points'] as int? ?? 0;
        final totalPlayers = ranking.length;

        String title, body;
        if (position <= 3) {
          title = '🏆 ¡Top 3 en Collique!';
          body =
              'Quedaste #$position esta semana con $totalPoints pts. ¡Sigue así!';
        } else if (position <= 10) {
          title = '🥇 Entre los 10 mejores';
          body =
              'Quedaste #$position de $totalPlayers vecinos esta semana. ¡Sigue participando!';
        } else {
          title = '📊 Tu ranking semanal';
          body =
              'Quedaste #$position de $totalPlayers vecinos esta semana. ¡Participa más para subir!';
        }

        await _notificationService.showAlertNotification(
          id: 999,
          title: title,
          body: body,
          payload: 'ranking',
        );

        // Solo guardar la semana si logramos mostrar la notificación
        await prefs.setInt('last_ranking_week', currentWeek);
      }
    } catch (e) {
      debugPrint('HomeScreen: Error en ranking semanal: $e');
    }
  }

  /// Calcula el número de semana desde época (simplificado, sin edge cases ISO).
  int _getIsoWeek(DateTime date) {
    return date.millisecondsSinceEpoch ~/ (Duration.millisecondsPerDay * 7);
  }

  /// Archiva reportes antiguos una sola vez al iniciar la app.
  Future<void> _archiveOldReportsOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastArchiveDay = prefs.getInt('last_archive_day') ?? 0;
      final today =
          DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

      // Solo archivar una vez al día
      if (today != lastArchiveDay) {
        final archived = await ReportService().archiveOldReports();
        if (archived > 0) {
          debugPrint(
            'HomeScreen: $archived reportes archivados automáticamente',
          );
        }
        await prefs.setInt('last_archive_day', today);
      }
    } catch (e) {
      debugPrint('HomeScreen: Error archivando reportes: $e');
    }
  }

  /// Verifica los créditos y muestra el banner si están bajos
  void _checkCredits() {
    if (_creditWarningDismissed) return;
    if (ZoneBotService.isPremium) {
      _creditWarningVisible = false;
      return;
    }
    final msgTokens = ZoneBotService.messageTokens;
    final resetTokens = ZoneBotService.resetTokens;
    if (msgTokens <= 5 || resetTokens <= 1) {
      if (mounted && !_creditWarningVisible) {
        setState(() => _creditWarningVisible = true);
        _creditWarningController.forward();
        // Mostrar tutorial después de que el banner termine de animarse
        Future.delayed(const Duration(milliseconds: 1000), () {
          _showCreditBannerTutorial();
        });
      }
    }
  }

  /// Va directo al tab Premium
  void _goToPremiumTab() {
    HapticFeedback.lightImpact();
    _soundService.play('nav_tap');
    _dismissTutorial();
    setState(() {
      _currentIndex = 5; // Premium tab
      _creditWarningDismissed = true;
      _creditWarningVisible = false;
    });
  }

  /// Muestra el tutorial del banner de créditos (solo primera vez)
  Future<void> _showCreditBannerTutorial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadySeen = prefs.getBool(_prefsCreditTutorialSeen) ?? false;
      if (alreadySeen || !mounted) return;

      await prefs.setBool(_prefsCreditTutorialSeen, true);
      if (!mounted) return;

      setState(() => _showCreditTutorial = true);

      // Auto-dismiss después de 5 segundos
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _dismissTutorial();
      });
    } catch (e) {
      debugPrint('HomeScreen: Error con tutorial de créditos: $e');
    }
  }

  /// Oculta el tutorial del banner
  void _dismissTutorial() {
    if (_showCreditTutorial && mounted) {
      setState(() => _showCreditTutorial = false);
    }
  }

  @override
  void dispose() {
    _incomingSosTimer?.cancel();
    _sosRealtimeService.incomingAlert.removeListener(_onIncomingSosAlert);
    _sosRealtimeService.stop(clearState: true);
    _welcomeController.dispose();
    _creditWarningController.dispose();
    _tutorialHandController.dispose();
    _supabaseService.unsubscribeFromRoboNotifications();
    super.dispose();
  }

  void _onIncomingSosAlert() {
    final alert = _sosRealtimeService.incomingAlert.value;
    if (alert == null || !mounted) return;

    _incomingSosTimer?.cancel();
    setState(() => _incomingSosAlert = alert);
    unawaited(
      _soundService.playSosReceivedAlert().then((_) {
        if (kDebugMode) debugPrint('[SOS][sound] played');
      }),
    );
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
    _notificationService.showSosAlert(userCode: alert.userCode);

    _incomingSosTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _incomingSosAlert = null);
    });
  }

  void _openIncomingSosOnMap() {
    setState(() {
      _currentIndex = 1;
      _incomingSosAlert = null;
    });
    _incomingSosTimer?.cancel();
  }

  /// Abre ZoneBot con sonido y transición slide-up
  void _openZoneBot() {
    HapticFeedback.lightImpact();
    _soundService.play('zonebot_open');
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ZoneBotScreen(userCode: widget.userCode, zone: widget.zone),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // === CONTENIDO PRINCIPAL ===
          Column(
            children: [
              Expanded(
                child: IndexedStack(index: _currentIndex, children: _screens),
              ),
              // Banner de créditos bajos (visible antes del bottom nav)
              _buildCreditWarningBanner(),
              _buildBottomNav(),
            ],
          ),

          // === WELCOME OVERLAY ===
          if (_showWelcome)
            AnimatedBuilder(
              animation: _welcomeController,
              builder: (context, child) {
                return IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: 0.4 * (1 - _welcomeController.value),
                    ),
                    child: Center(
                      child: Opacity(
                        opacity: 1.0 - _welcomeOpacity.value,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '¡Bienvenido a SafeZone!',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Zona ${widget.zone} · Collique',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // === TUTORIAL OVERLAY (primera vez que aparece el banner) ===
          if (_showCreditTutorial) _buildCreditTutorialOverlay(),

          // === GLOBO ZONEBOT (arrastrable) ===
          if (_bubbleReady)
            Positioned(
              left: _bubbleLeft,
              top: _bubbleTop,
              child: ZoneBotBubble(
                onTap: _openZoneBot,
                onDragUpdate: (Offset delta) {
                  setState(() {
                    _bubbleLeft += delta.dx;
                    _bubbleTop += delta.dy;
                  });
                },
                onDragEnd: _saveBubblePosition,
              ),
            ),

          if (_incomingSosAlert != null) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.sosRed, width: 5),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              left: 12,
              right: 12,
              child: Material(
                color: AppTheme.sosRed,
                elevation: 12,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _openIncomingSosOnMap,
                  borderRadius: BorderRadius.circular(14),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.sos, color: Colors.white, size: 30),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ALERTA S.O.S. CERCANA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Toca para ver la ubicación aproximada en el mapa.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Overlay animado del tutorial — mano señalando + texto shimmer + fondo semitransparente
  Widget _buildCreditTutorialOverlay() {
    return GestureDetector(
      onTap: _dismissTutorial,
      child: Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Mano señalando hacia abajo
            AnimatedBuilder(
              animation: _tutorialHandController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset.zero,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Texto con shimmer
                      Shimmer.fromColors(
                        baseColor: Colors.amber.shade300,
                        highlightColor: Colors.white,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app,
                                color: Colors.white,
                                size: 22,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '¡Toca aquí para ver Premium!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Flecha animada apuntando hacia abajo
                      _AnimatedArrowDown(controller: _tutorialHandController),
                    ],
                  ),
                );
              },
            ),
            // Espacio para el banner (se ve debajo)
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  /// Banner animado de créditos bajos — aparece cuando quedan ≤5 mensajes o ≤1 reset
  Widget _buildCreditWarningBanner() {
    if (!_creditWarningVisible || ZoneBotService.isPremium) {
      return const SizedBox.shrink();
    }

    final msgTokens = ZoneBotService.messageTokens;
    final resetTokens = ZoneBotService.resetTokens;
    final isCritical = msgTokens <= 2 || resetTokens <= 0;

    return AnimatedBuilder(
      animation: _creditWarningController,
      builder: (context, child) {
        final slideOffset = (1.0 - _creditWarningController.value) * 60.0;
        final opacity = _creditWarningController.value;

        return Transform.translate(
          offset: Offset(0, slideOffset),
          child: Opacity(
            opacity: opacity,
            child: GestureDetector(
              onTap: _goToPremiumTab,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isCritical
                        ? [Colors.red.shade700, Colors.orange.shade800]
                        : [Colors.amber.shade600, Colors.orange.shade600],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isCritical ? Colors.red : Colors.amber)
                          .withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      // Icono animado
                      _AnimatedWarningIcon(isCritical: isCritical),
                      const SizedBox(width: 10),
                      // Texto
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isCritical
                                  ? '⚠️ ¡Te quedan pocos créditos!'
                                  : '🌟 Tus créditos se están agotando',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$msgTokens mensajes • $resetTokens resets — '
                              'Toca para ver Premium ♾️',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Flecha
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Construye un icono animado para la navegación con tooltip al mantener presionado
  Widget _buildNavIcon(AnimatedNavIconType type, bool active) {
    final tooltip = switch (type) {
      AnimatedNavIconType.muro => 'Muro de reportes · Noticias de la comunidad',
      AnimatedNavIconType.mapa => 'Mapa de riesgo en tiempo real',
      AnimatedNavIconType.sos => 'Emergencia · Alerta S.O.S. inmediata',
      AnimatedNavIconType.chat => 'Chat anónimo con tus vecinos',
      AnimatedNavIconType.reportar => 'Reportar un incidente',
      AnimatedNavIconType.premium => 'Premium · Créditos ilimitados ♾️',
    };
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      verticalOffset: 12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      child: AnimatedNavIcon(type: type, isActive: active, size: 22),
    );
  }

  /// Bottom nav con sonidos y haptic en cada tap
  Widget _buildBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkCard : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              if (index != _currentIndex) {
                HapticFeedback.selectionClick();
                _soundService.play('nav_tap');
              }
              setState(() => _currentIndex = index);
            },
            selectedItemColor: AppTheme.primaryGreen,
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            backgroundColor: bgColor,
            elevation: 0,
            selectedFontSize: 11,
            unselectedFontSize: 10,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            items: [
              BottomNavigationBarItem(
                icon: _buildNavIcon(AnimatedNavIconType.muro, false),
                activeIcon: _buildNavIcon(AnimatedNavIconType.muro, true),
                label: 'Muro',
              ),
              BottomNavigationBarItem(
                icon: _buildNavIcon(AnimatedNavIconType.mapa, false),
                activeIcon: _buildNavIcon(AnimatedNavIconType.mapa, true),
                label: 'Mapa',
              ),
              BottomNavigationBarItem(
                icon: _buildNavIcon(AnimatedNavIconType.sos, false),
                activeIcon: _buildNavIcon(AnimatedNavIconType.sos, true),
                label: 'S.O.S.',
              ),
              BottomNavigationBarItem(
                icon: _buildNavIcon(AnimatedNavIconType.chat, false),
                activeIcon: _buildNavIcon(AnimatedNavIconType.chat, true),
                label: 'Chat',
              ),
              BottomNavigationBarItem(
                icon: _buildNavIcon(AnimatedNavIconType.reportar, false),
                activeIcon: _buildNavIcon(AnimatedNavIconType.reportar, true),
                label: 'Reportar',
              ),
              // Premium tab — acceso directo a suscripción
              BottomNavigationBarItem(
                icon: _buildNavIcon(AnimatedNavIconType.premium, false),
                activeIcon: _buildNavIcon(AnimatedNavIconType.premium, true),
                label: 'Premium',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ANIMATED WARNING ICON — Icono pulsante para banner de créditos
// ============================================================

class _AnimatedWarningIcon extends StatefulWidget {
  final bool isCritical;

  const _AnimatedWarningIcon({required this.isCritical});

  @override
  State<_AnimatedWarningIcon> createState() => _AnimatedWarningIconState();
}

class _AnimatedWarningIconState extends State<_AnimatedWarningIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.isCritical ? Icons.battery_alert : Icons.battery_std,
            color: Colors.white,
            size: 18,
          ),
        );
      },
    );
  }
}

// ============================================================
// ANIMATED ARROW DOWN — Flecha pulsante que señala el banner
// ============================================================

class _AnimatedArrowDown extends StatelessWidget {
  final AnimationController controller;

  const _AnimatedArrowDown({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(40, 50),
          painter: _ArrowDownPainter(progress: controller.value),
        );
      },
    );
  }
}

class _ArrowDownPainter extends CustomPainter {
  final double progress;

  _ArrowDownPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Círculo exterior pulsante
    final circlePaint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.3 + progress * 0.4)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(centerX, centerY), 16 + progress * 4, circlePaint);

    // Flecha hacia abajo
    final arrowPaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Línea vertical
    canvas.drawLine(
      Offset(centerX, 8),
      Offset(centerX, centerY + 8),
      arrowPaint,
    );

    // Punta de flecha
    final arrowHead = Path();
    arrowHead.moveTo(centerX - 10, centerY);
    arrowHead.lineTo(centerX, centerY + 12);
    arrowHead.lineTo(centerX + 10, centerY);

    canvas.drawPath(arrowHead, arrowPaint);
  }

  @override
  bool shouldRepaint(_ArrowDownPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
