import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/app.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/zonebot_service.dart';
import 'package:safezone/services/report_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/screens/premium/premium_screen.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/widgets/confetti_overlay.dart';
import 'package:timeago/timeago.dart' as timeago;

class StatsScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const StatsScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with TickerProviderStateMixin {
  final SupabaseService _supabase = SupabaseService();

  int _reportCount = 0;
  int _reactionCount = 0;
  int _sosCount = 0;
  bool _isLoadingStats = true;

  // Sistema de Puntos Vecinales
  Map<String, dynamic>? _vecinoLevel;
  bool _isLoadingVecino = true;

  // 🎊 Celebración de subida de nivel
  bool _showLevelUpCelebration = false;
  String _celebrationMessage = '';
  bool _didJustLevelUp = false;

  // 🏅 Ranking vecinal
  List<Map<String, dynamic>> _ranking = [];
  bool _isLoadingRanking = false;
  bool _showRanking = false;

  // Historial de reportes archivados
  List<Report> _archivedReports = [];
  bool _isLoadingArchived = false;
  bool _showArchived = false;

  // Animaciones
  late AnimationController _sparkleController;
  late AnimationController _badgePulseController;

  @override
  void initState() {
    super.initState();
    _loadStats();

    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _badgePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void dispose() {
    _sparkleController.dispose();
    _badgePulseController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final reportsResult = await _supabase.client
          .from('reports')
          .select('id')
          .eq('user_code', widget.userCode);
      final reportCount = (reportsResult as List).length;

      final archivedResult = await _supabase.client
          .from('archived_reports')
          .select('id')
          .eq('user_code', widget.userCode);
      final archivedCount = (archivedResult as List).length;

      final reactionsResult = await _supabase.client
          .from('reactions')
          .select('id')
          .eq('user_code', widget.userCode);
      final reactionCount = (reactionsResult as List).length;

      final sosResult = await _supabase.client
          .from('sos_alerts')
          .select('id')
          .eq('user_code', widget.userCode);
      final sosCount = (sosResult as List).length;

      // Cargar nivel vecinal
      await _loadVecinoLevel();

      if (mounted) {
        setState(() {
          _reportCount = reportCount + archivedCount;
          _reactionCount = reactionCount;
          _sosCount = sosCount;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('StatsScreen: Error cargando estadísticas: $e');
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  /// Carga el nivel y puntos del vecino desde Supabase
  Future<void> _loadVecinoLevel() async {
    try {
      final level = await _supabase.getVecinoLevel(widget.userCode);
      if (mounted) {
        setState(() {
          _vecinoLevel = level;
          _isLoadingVecino = false;
        });
      }
      // Verificar si subió de nivel y mostrar celebración
      final newLevel = await _checkLevelUp();
      if (newLevel != null && mounted) {
        _triggerLevelUpCelebration(newLevel);
      }
    } catch (e) {
      debugPrint('StatsScreen: Error cargando nivel vecinal: $e');
      if (mounted) setState(() => _isLoadingVecino = false);
    }
  }

  /// Carga los reportes archivados del usuario
  Future<void> _loadArchivedReports() async {
    if (_isLoadingArchived) return;
    setState(() => _isLoadingArchived = true);
    try {
      final reports = await ReportService().getArchivedReports(
        zone: widget.zone,
        limit: 100,
      );
      if (mounted) {
        setState(() {
          _archivedReports = reports;
          _isLoadingArchived = false;
          _showArchived = true;
        });
      }
    } catch (e) {
      debugPrint('StatsScreen: Error cargando historial: $e');
      if (mounted) setState(() => _isLoadingArchived = false);
    }
  }

  void _goToPremium() {
    // Navegar a la pantalla Premium (necesita userCode y zone)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PremiumScreen(
          userCode: widget.userCode,
          zone: widget.zone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPremium = ZoneBotService.isPremium;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.sectionPerfil,
        title: Text(isPremium ? 'Mi Perfil ⭐' : 'Mi Perfil'),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => SafeZoneAppState.instance?.toggleTheme(),
            tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ============================================================
              // AVATAR + BADGE PREMIUM ANIMADO
              // ============================================================
              Stack(
                children: [
                  // Sparkles around avatar (solo premium)
                  if (isPremium)
                    AnimatedBuilder(
                      animation: _sparkleController,
                      builder: (context, child) {
                        return CustomPaint(
                          size: const Size(140, 140),
                          painter: _SparklePainter(
                            progress: _sparkleController.value,
                            color: Colors.amber,
                          ),
                        );
                      },
                    ),

                  // Avatar shield
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isPremium
                          ? Colors.amber.withValues(alpha: 0.15)
                          : AppTheme.primaryGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: isPremium
                          ? Border.all(
                              color: Colors.amber.withValues(alpha: 0.4),
                              width: 2,
                            )
                          : null,
                    ),
                    child: Icon(
                      isPremium ? Icons.star : Icons.shield,
                      size: 64,
                      color: isPremium ? Colors.amber : AppTheme.primaryGreen,
                    ),
                  ),

                  // Premium badge flotante
                  if (isPremium)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: AnimatedBuilder(
                        animation: _badgePulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: 1.0 + _badgePulseController.value * 0.12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.amber,
                                    Colors.orange,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amber.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star,
                                      size: 14, color: Colors.black87),
                                  SizedBox(width: 4),
                                  Text(
                                    'PREMIUM',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // User code + info
              Text(
                widget.userCode,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isPremium
                      ? Colors.amber.withValues(alpha: 0.12)
                      : AppTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Zona ${widget.zone} • Collique',
                  style: TextStyle(
                    fontSize: 13,
                    color: isPremium ? Colors.amber.shade700 : AppTheme.primaryGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Identidad anónima',
                style: TextStyle(fontSize: 12, color: mutedColor),
              ),

              const SizedBox(height: 24),

              // ============================================================
              // NIVEL VECINAL
              // ============================================================
              _buildVecinoLevelCard(isDark, textColor, mutedColor),

              const SizedBox(height: 20),

              // ============================================================
              // CARD DE SUSCRIPCIÓN PREMIUM
              // ============================================================
              _buildPremiumCard(isDark, isPremium, textColor, mutedColor),

              const SizedBox(height: 20),

              // ============================================================
              // STATS CARDS
              // ============================================================
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.newspaper,
                      label: 'Reportes',
                      value: _isLoadingStats ? '...' : '$_reportCount',
                      color: AppTheme.primaryGreen,
                      cardColor: cardColor,
                      textColor: textColor,
                      mutedColor: mutedColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.shield,
                      label: 'Reacciones',
                      value: _isLoadingStats ? '...' : '$_reactionCount',
                      color: AppTheme.shieldBlue,
                      cardColor: cardColor,
                      textColor: textColor,
                      mutedColor: mutedColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.sos,
                      label: 'Alertas SOS',
                      value: _isLoadingStats ? '...' : '$_sosCount',
                      color: AppTheme.sosRed,
                      cardColor: cardColor,
                      textColor: textColor,
                      mutedColor: mutedColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Info card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu información',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(
                      icon: Icons.code,
                      label: 'Código',
                      value: widget.userCode,
                      textColor: textColor,
                      mutedColor: mutedColor,
                    ),
                    const Divider(height: 24),
                    _InfoRow(
                      icon: Icons.map,
                      label: 'Zona',
                      value: 'Zona ${widget.zone} - Collique, Comas',
                      textColor: textColor,
                      mutedColor: mutedColor,
                    ),
                    const Divider(height: 24),
                    _InfoRow(
                      icon: isDark ? Icons.light_mode : Icons.dark_mode,
                      label: 'Tema',
                      value: isDark ? 'Oscuro' : 'Claro',
                      textColor: textColor,
                      mutedColor: mutedColor,
                      trailing: Switch(
                        value: isDark,
                        onChanged: (_) =>
                            SafeZoneAppState.instance?.toggleTheme(),
                        activeThumbColor: AppTheme.primaryLight,
                      ),
                    ),
                    if (isPremium) ...[
                      const Divider(height: 24),
                      _InfoRow(
                        icon: Icons.star,
                        label: 'Suscripción',
                        value: 'Premium activo ♾️',
                        textColor: textColor,
                        mutedColor: mutedColor,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Activo',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // About
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SafeZone',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Red vecinal de seguridad de Collique, Comas.\n'
                      'Versión 1.0.0',
                      style: TextStyle(
                        fontSize: 13,
                        color: mutedColor,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ============================================================
              // 🏅 RANKING VECINAL
              // ============================================================
              _buildRankingSection(isDark, textColor, mutedColor, cardColor),

              const SizedBox(height: 24),

              // ============================================================
              // HISTORIAL DE REPORTES ARCHIVADOS
              // ============================================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    GestureDetector(
                      onTap: () {
                        if (!_showArchived) {
                          _loadArchivedReports();
                        } else {
                          setState(() => _showArchived = false);
                        }
                      },
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.shieldBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.archive_outlined,
                                size: 20, color: AppTheme.shieldBlue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Historial de reportes',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  'Reportes archivados > 7 días',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: mutedColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedRotation(
                            turns: _showArchived ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.expand_more,
                              color: mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Lista de reportes archivados
                    if (_showArchived) ...[
                      const SizedBox(height: 16),
                      if (_isLoadingArchived)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_archivedReports.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'No hay reportes archivados aún',
                              style: TextStyle(color: mutedColor, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _archivedReports.length.clamp(0, 10),
                          separatorBuilder: (_, _) =>
                              const Divider(height: 16),
                          itemBuilder: (context, index) {
                            final report = _archivedReports[index];
                            return Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Report.categoryColorFor(
                                            report.category)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Report.categoryIconFor(report.category),
                                    size: 16,
                                    color: Report.categoryColorFor(
                                        report.category),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        report.description.length > 50
                                            ? '${report.description.substring(0, 50)}...'
                                            : report.description,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${timeago.format(report.createdAt, locale: 'es')} · Zona ${report.zone}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: mutedColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Report.categoryColorFor(
                                            report.category)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    Report.categoryLabelFor(report.category),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Report.categoryColorFor(
                                          report.category),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),

          // 🎊 Confetti overlay para celebración de subida de nivel
          if (_showLevelUpCelebration)
            Positioned.fill(
              child: IgnorePointer(
                child: ConfettiOverlay(
                  particleCount: 80,
                  duration: const Duration(milliseconds: 2800),
                ),
              ),
            ),

          // 🎉 Card de celebración de nivel
          if (_didJustLevelUp)
            Positioned(
              top: 100,
              left: 32,
              right: 32,
              child: IgnorePointer(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.amber.shade400,
                          Colors.orange.shade600,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '🎉',
                          style: TextStyle(fontSize: 48),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '¡FELICIDADES!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Has alcanzado el nivel $_celebrationMessage',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sigue así, ¡tu comunidad te necesita! 🛡️',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Detecta si el usuario subió de nivel comparando con SharedPreferences.
  Future<String?> _checkLevelUp() async {
    if (_vecinoLevel == null) return null;
    final levelName = _vecinoLevel!['level'] as String?;
    if (levelName == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final previousLevel = prefs.getString('last_saved_level');
      
      // Guardar nivel actual
      await prefs.setString('last_saved_level', levelName);

      // Si no hay nivel previo o es el mismo, no celebrar
      if (previousLevel == null || previousLevel == levelName) return null;

      // Verificar que el nivel actual sea mejor (tiene más emojis = más alto)
      final emojiCount = levelName.runes.where((r) => r > 0xFF00).length;
      final prevEmojiCount = previousLevel.runes.where((r) => r > 0xFF00).length;
      if (emojiCount <= prevEmojiCount) return null;

      return levelName;
    } catch (e) {
      return null;
    }
  }

  /// Muestra la celebración de subida de nivel.
  void _triggerLevelUpCelebration(String newLevel) {
    setState(() {
      _didJustLevelUp = true;
      _celebrationMessage = newLevel;
    });

    SoundService().play('happy');

    // Mostrar confetti
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _showLevelUpCelebration = true);
        
        // Ocultar confetti después de la animación
        Future.delayed(const Duration(milliseconds: 3000), () {
          if (mounted) {
            setState(() {
              _showLevelUpCelebration = false;
              _didJustLevelUp = false;
            });
          }
        });
      }
    }    );
  }

  // ============================================================
  // 🏅 RANKING VECINAL
  // ============================================================

  /// Carga el ranking de vecinos
  Future<void> _loadRanking() async {
    if (_isLoadingRanking) return;
    setState(() => _isLoadingRanking = true);
    try {
      final ranking = await _supabase.getRanking(limit: 10);
      if (mounted) {
        setState(() {
          _ranking = ranking;
          _isLoadingRanking = false;
          _showRanking = true;
        });
      }
    } catch (e) {
      debugPrint('StatsScreen: Error cargando ranking: $e');
      if (mounted) setState(() => _isLoadingRanking = false);
    }
  }

  /// Sección de ranking vecinal con podio
  Widget _buildRankingSection(
      bool isDark, Color textColor, Color mutedColor, Color cardColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header expandible
          GestureDetector(
            onTap: () {
              if (!_showRanking) {
                _loadRanking();
              } else {
                setState(() => _showRanking = false);
              }
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.emoji_events,
                      size: 20, color: Colors.amber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🏅 Ranking Vecinal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      Text(
                        'Top 10 vecinos de Collique',
                        style: TextStyle(
                          fontSize: 12,
                          color: mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _showRanking ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, color: mutedColor),
                ),
              ],
            ),
          ),

          if (_showRanking) ...[
            const SizedBox(height: 16),
            if (_isLoadingRanking)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_ranking.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'Aún no hay suficientes datos para mostrar el ranking.\n¡Sé el primero en participar!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedColor, fontSize: 13, height: 1.5),
                  ),
                ),
              )
            else ...[
              // Podio (top 3)
              _buildPodium(isDark, textColor, mutedColor),
              const SizedBox(height: 16),
              // Lista completa (4-10)
              ...List.generate(
                _ranking.length.clamp(0, 10),
                (index) {
                  if (index >= 3 && index < _ranking.length) {
                    final item = _ranking[index];
                    return _buildRankingRow(index + 1, item, isDark, textColor, mutedColor);
                  }
                  return const SizedBox.shrink();
                },
              ).where((w) => w is! SizedBox),
            ],
          ],
        ],
      ),
    );
  }

  /// Podium animado para top 3
  Widget _buildPodium(bool isDark, Color textColor, Color mutedColor) {
    if (_ranking.isEmpty) return const SizedBox.shrink();

    // Obtener top 3 (o menos si no hay suficientes)
    final top3 = _ranking.length >= 3 ? _ranking.sublist(0, 3) : _ranking;

    // Reordenar: 2°, 1°, 3° para mostrar en podio
    final podiumOrder = <Map<String, dynamic>>[];
    if (top3.length >= 2) podiumOrder.add(top3[1]); // Segundo
    if (top3.isNotEmpty) podiumOrder.add(top3[0]); // Primero
    if (top3.length >= 3) podiumOrder.add(top3[2]); // Tercero

    final podiumHeights = [80.0, 110.0, 60.0];
    final podiumColors = [
      const Color(0xFF78909C), // Plata
      const Color(0xFFFFD600), // Oro
      const Color(0xFFA1887F), // Bronce
    ];
    final podiumLabels = ['🥈', '🥇', '🥉'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(podiumOrder.length, (index) {
          final item = podiumOrder[index];
          final userCode = item['user_code'] as String? ?? 'Anónimo';
          final totalPoints = item['total_points'] as int? ?? 0;
          final height = podiumHeights[index];
          final color = podiumColors[index];
          final label = podiumLabels[index];

          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      userCode.length >= 2
                          ? userCode.substring(userCode.length - 2).toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalPoints pts',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                // Barra del podio
                Container(
                  width: 40,
                  height: height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.6),
                        color.withValues(alpha: 0.3),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// Fila individual del ranking (posiciones 4+) 
  Widget _buildRankingRow(int rank, Map<String, dynamic> item,
      bool isDark, Color textColor, Color mutedColor) {
    final userCode = item['user_code'] as String? ?? 'Anónimo';
    final totalPoints = item['total_points'] as int? ?? 0;
    final level = item['level'] as String? ?? '👤 Residente';
    final reportCount = item['report_count'] as int? ?? 0;
    final checkinCount = item['checkin_count'] as int? ?? 0;

    final isMe = userCode == widget.userCode;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMe
            ? AppTheme.primaryGreen.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isMe
            ? Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          // Posición
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isMe
                  ? AppTheme.primaryGreen.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isMe ? AppTheme.primaryGreen : mutedColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Avatar mini
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isMe
                  ? AppTheme.primaryGreen.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                userCode.length >= 2
                    ? userCode.substring(userCode.length - 2).toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isMe ? AppTheme.primaryGreen : mutedColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Código de usuario
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      userCode,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                        color: isMe ? AppTheme.primaryGreen : textColor,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'TÚ',
                          style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '$level · $reportCount reportes · $checkinCount check-ins',
                  style: TextStyle(fontSize: 10, color: mutedColor),
                ),
              ],
            ),
          ),
          // Puntos
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isMe
                  ? AppTheme.primaryGreen.withValues(alpha: 0.12)
                  : Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$totalPoints pts',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isMe ? AppTheme.primaryGreen : Colors.amber.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Card de Nivel Vecinal — muestra puntos, nivel y progreso
  Widget _buildVecinoLevelCard(bool isDark, Color textColor, Color mutedColor) {
    if (_isLoadingVecino) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final totalPoints = _vecinoLevel?['total_points'] as int? ?? 0;
    final levelName = _vecinoLevel?['level'] as String? ?? '👤 Residente';
    final nextLevelPoints = _vecinoLevel?['next_level_points'] as int? ?? 5;

    // Determinar el progreso hacia el siguiente nivel
    // Niveles: 0→5 (Residente→Nuevo Vecino), 5→20 (Nuevo Vecino→Vecino Activo), 
    // 20→50 (Vecino Activo→Protector), 50→100 (Protector→Vigilante)
    double progress;
    String progressLabel;
    if (totalPoints >= 100) {
      progress = 1.0;
      progressLabel = '🏆 Nivel máximo alcanzado';
    } else if (totalPoints >= 50) {
      progress = (totalPoints - 50) / 50.0;
      progressLabel = '$nextLevelPoints pts para 🥇 Vigilante';
    } else if (totalPoints >= 20) {
      progress = (totalPoints - 20) / 30.0;
      progressLabel = '$nextLevelPoints pts para 🥈 Protector';
    } else if (totalPoints >= 5) {
      progress = (totalPoints - 5) / 15.0;
      progressLabel = '$nextLevelPoints pts para 🥉 Vecino Activo';
    } else {
      progress = totalPoints / 5.0;
      progressLabel = '$nextLevelPoints pts para 🌱 Nuevo Vecino';
    }
    
    final levelColor = totalPoints >= 100 
        ? Colors.amber
        : totalPoints >= 50 
            ? Colors.blueGrey
            : totalPoints >= 20
                ? AppTheme.primaryGreen
                : totalPoints >= 5
                    ? Colors.teal
                    : mutedColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            levelColor.withValues(alpha: 0.1),
            levelColor.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: levelColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: levelColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icono + Título
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.emoji_events, color: levelColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      levelName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '$totalPoints pts vecinales',
                      style: TextStyle(
                        fontSize: 13,
                        color: levelColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Barra de progreso
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: levelColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(levelColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            progressLabel,
            style: TextStyle(
              fontSize: 11,
              color: mutedColor,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 12),

          // Mini guía de puntos
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gana puntos:',
                  style: TextStyle(
                    fontSize: 11,
                    color: mutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildPointRow(mutedColor, '+10 pts', 'Reportar incidente', Icons.newspaper, levelColor),
                const SizedBox(height: 4),
                _buildPointRow(mutedColor, '+5 pts', 'Reaccionar', Icons.thumb_up_outlined, levelColor),
                const SizedBox(height: 4),
                _buildPointRow(mutedColor, '+20 pts', 'Activar SOS', Icons.sos, levelColor),
                const SizedBox(height: 4),
                _buildPointRow(mutedColor, '+3 pts', 'Check-in zona segura ✅', Icons.check_circle_outline, levelColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointRow(Color mutedColor, String pts, String label, IconData icon, Color levelColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: levelColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 12, color: levelColor),
        ),
        const SizedBox(width: 8),
        Text(
          pts,
          style: TextStyle(
            fontSize: 12,
            color: levelColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: mutedColor,
          ),
        ),
      ],
    );
  }

  /// Card de suscripción premium — animado con CTA
  Widget _buildPremiumCard(
      bool isDark, bool isPremium, Color textColor, Color mutedColor) {

    return GestureDetector(
      onTap: isPremium ? null : _goToPremium,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: isPremium
              ? LinearGradient(
                  colors: [
                    Colors.amber.shade50,
                    Colors.orange.shade50,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    AppTheme.primaryGreen.withValues(alpha: 0.08),
                    AppTheme.primaryDark.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPremium
                ? Colors.amber.withValues(alpha: 0.4)
                : AppTheme.primaryGreen.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isPremium
                  ? Colors.amber.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icono
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isPremium
                    ? Colors.amber.withValues(alpha: 0.2)
                    : AppTheme.primaryGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isPremium ? Icons.star : Icons.star_outline,
                color: isPremium ? Colors.amber.shade700 : AppTheme.primaryGreen,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),

            // Texto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPremium ? '⭐ Premium activo' : '🌟 SafeZone Premium',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isPremium
                        ? 'Disfruta de todos los beneficios ilimitados'
                        : '♾️ Tickets ilimitados para ZoneBot',
                    style: TextStyle(
                      fontSize: 12,
                      color: mutedColor,
                    ),
                  ),
                ],
              ),
            ),

            // Flecha / Badge
            if (isPremium)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '✓ Activo',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ver planes',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios,
                        size: 10, color: Colors.white),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SPARKLE PAINTER — Partículas animadas alrededor del avatar
// ============================================================

class _SparklePainter extends CustomPainter {
  final double progress;
  final Color color;

  _SparklePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * pi * 2 + progress * pi * 2;
      final distance = radius * 0.65 + (progress * 0.2 * radius);
      final x = center.dx + distance * cos(angle);
      final y = center.dy + distance * sin(angle);

      final sparkleSize = 2.0 + (progress * 2.0);
      final opacity = ((progress + i * 0.15) % 1.0);

      paint.color = color.withValues(alpha: 0.3 + opacity * 0.4);
      canvas.drawCircle(Offset(x, y), sparkleSize, paint);

      // Dibujar cruz de estrella
      final crossPaint = Paint()
        ..color = color.withValues(alpha: 0.2 + opacity * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawLine(
        Offset(x - 4, y),
        Offset(x + 4, y),
        crossPaint,
      );
      canvas.drawLine(
        Offset(x, y - 4),
        Offset(x, y + 4),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ============================================================
// STAT CARD
// ============================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color cardColor;
  final Color textColor;
  final Color mutedColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.cardColor,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              value,
              key: ValueKey(value),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INFO ROW
// ============================================================

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textColor;
  final Color mutedColor;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.textColor,
    required this.mutedColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: mutedColor),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: mutedColor)),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
