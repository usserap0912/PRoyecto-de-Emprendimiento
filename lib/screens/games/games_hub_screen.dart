import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/games/trivia_game_screen.dart';
import 'package:safezone/screens/games/patrol_game_screen.dart';

class GamesHubScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const GamesHubScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends State<GamesHubScreen>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _cardsController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _cardsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _cardsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zona de Juegos'),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.brandRedDark, AppTheme.brandRedBright],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF16213E), const Color(0xFF0F3460)]
                : [const Color(0xFFF5F5F5), const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // === Encabezado con animación ===
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, _) {
                  return _buildHeader(isDark);
                },
              ),
              const SizedBox(height: 32),

              // === Tarjeta 1: Trivia ===
              _buildAnimatedCard(
                index: 0,
                child: _GameCardV2(
                  title: 'Trivia de Seguridad\nCollique',
                  subtitle:
                      'Pon a prueba tus conocimientos sobre prevención de riesgos, números de emergencia y geografía local. Responde rápido para ganar más puntos.',
                  icon: Icons.psychology,
                  gradientColors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  accentColor: const Color(0xFF42A5F5),
                  emoji: '🧠',
                  stats: '15 preguntas • 3 vidas • Contrarreloj',
                  glowColor: const Color(0xFF1565C0).withValues(alpha: 0.3),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TriviaGameScreen(
                          userCode: widget.userCode,
                          zone: widget.zone,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // === Tarjeta 2: Patrullaje ===
              _buildAnimatedCard(
                index: 1,
                child: _GameCardV2(
                  title: 'Patrullaje de\nla Revolución',
                  subtitle:
                      'Conduce por la Av. Revolución esquivando peligros y recolectando escudos de seguridad. La velocidad aumenta con el tiempo.',
                  icon: Icons.local_police,
                  gradientColors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                  accentColor: const Color(0xFF66BB6A),
                  emoji: '🚓',
                  stats: 'Arcade infinito • Mayor puntuación gana',
                  glowColor: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PatrolGameScreen(
                          userCode: widget.userCode,
                          zone: widget.zone,
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 32),

              // === Footer ===
              _buildFooter(isDark),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCard({required int index, required Widget child}) {
    final delay = index * 150;
    return AnimatedBuilder(
      animation: _cardsController,
      builder: (context, _) {
        final progress = (_cardsController.value * 1000 - delay)
            .clamp(0, 1000) / 1000;
        return Opacity(
          opacity: progress.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, 50 * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.brandRedDark, AppTheme.brandRedBright, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decoración de fondo
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            left: -10,
            bottom: -10,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Column(
            children: [
              // Icono animado
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, _) {
                  return Transform.scale(
                    scale: _pulseAnim.value,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.sports_esports_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text(
                '🕹️ Zona de Juegos',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aprende, juega y protege tu comunidad',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildFooterIcon(Icons.emoji_events, AppTheme.warningYellow),
            const SizedBox(width: 8),
            Text(
              '🎮 ¡Diviértete aprendiendo!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : Colors.black54,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Gana puntos y conviértete en el guardián de Collique',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white30 : Colors.black38,
          ),
        ),
      ],
    );
  }

  Widget _buildFooterIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

// ============================================================
// Game Card V2 - Mejorada visualmente
// ============================================================
class _GameCardV2 extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final Color accentColor;
  final String emoji;
  final String stats;
  final Color glowColor;
  final VoidCallback onTap;

  const _GameCardV2({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.accentColor,
    required this.emoji,
    required this.stats,
    required this.glowColor,
    required this.onTap,
  });

  @override
  State<_GameCardV2> createState() => _GameCardV2State();
}

class _GameCardV2State extends State<_GameCardV2>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _hoverController;
  late Animation<double> _hoverAnim;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _hoverAnim = Tween<double>(begin: 0.0, end: 6.0).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedBuilder(
        animation: Listenable.merge([_hoverController]),
        builder: (context, _) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: _isPressed
                ? (Matrix4.diagonal3Values(0.96, 0.96, 1.0))
                : Matrix4.identity(),
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: widget.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.glowColor,
                  blurRadius: 20 + _hoverAnim.value,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: widget.glowColor.withValues(alpha: 0.2),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fila superior: emoji + icono
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Emoji grande con glow
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(widget.emoji,
                              style: const TextStyle(fontSize: 36)),
                        ),
                        const Spacer(),
                        // Icono con fondo translúcido y glow
                        AnimatedBuilder(
                          animation: _hoverAnim,
                          builder: (context, _) {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Icon(widget.icon,
                                  size: 30, color: Colors.white),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Título
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.3,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Subtítulo
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.6,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    // Stats + flecha
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined,
                                  size: 13, color: Colors.white70),
                              const SizedBox(width: 6),
                              Text(
                                widget.stats,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
