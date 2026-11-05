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
import 'package:safezone/screens/report/report_form_screen.dart';
import 'package:safezone/widgets/app_tutorial.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/notification_service.dart';
import 'package:safezone/services/report_service.dart';
import 'package:safezone/widgets/animated_nav_icon.dart';
import 'package:safezone/models/sos_alert.dart';
import 'package:safezone/services/sos_realtime_service.dart';

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

  late final List<Widget> _screens;

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
      SoundService().play('welcome');
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

  @override
  void dispose() {
    _incomingSosTimer?.cancel();
    _sosRealtimeService.incomingAlert.removeListener(_onIncomingSosAlert);
    _sosRealtimeService.stop(clearState: true);
    _welcomeController.dispose();
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

  /// Construye un icono animado para la navegación con tooltip al mantener presionado
  Widget _buildNavIcon(AnimatedNavIconType type, bool active) {
    final tooltip = switch (type) {
      AnimatedNavIconType.muro => 'Muro de reportes · Noticias de la comunidad',
      AnimatedNavIconType.mapa => 'Mapa de riesgo en tiempo real',
      AnimatedNavIconType.sos => 'Emergencia · Alerta S.O.S. inmediata',
      AnimatedNavIconType.chat => 'Chat anónimo con tus vecinos',
      AnimatedNavIconType.reportar => 'Reportar un incidente',
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
            ],
          ),
        ),
      ),
    );
  }
}
