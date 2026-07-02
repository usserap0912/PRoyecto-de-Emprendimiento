import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/games/trivia_game_screen.dart';
import 'package:safezone/screens/games/patrol_game_screen.dart';

class GamesHubScreen extends StatelessWidget {
  final String userCode;
  final int zone;

  const GamesHubScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zona de Juegos'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // === Encabezado estilo arcade ===
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryGreen, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Icono arcade
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sports_esports,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '🕹️ Zona de Juegos',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aprende, juega y protege tu comunidad',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // === Tarjeta 1: Trivia de Seguridad ===
            _GameCard(
              title: 'Trivia de Seguridad\nCollique',
              subtitle:
                  'Pon a prueba tus conocimientos sobre prevención de riesgos, números de emergencia y geografía local. Responde rápido para ganar más puntos.',
              icon: Icons.quiz,
              gradientColors: const [Color(0xFF1565C0), Color(0xFF1976D2)],
              emoji: '🧠',
              stats: '15 preguntas • 3 vidas • Modo contrarreloj',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TriviaGameScreen(
                      userCode: userCode,
                      zone: zone,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // === Tarjeta 2: Patrullaje de la Revolución ===
            _GameCard(
              title: 'Patrullaje de\nla Revolución',
              subtitle:
                  'Conduce por la Av. Revolución esquivando peligros y recolectando escudos de seguridad. La velocidad aumenta con el tiempo.',
              icon: Icons.directions_car,
              gradientColors: const [Color(0xFF2E7D32), Color(0xFF388E3C)],
              emoji: '🚓',
              stats: 'Arcade infinito • Mayor puntuación gana',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PatrolGameScreen(
                      userCode: userCode,
                      zone: zone,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // === Footer decorativo ===
            Text(
              '🎮 ¡Diviértete aprendiendo!',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black38,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final String emoji;
  final String stats;
  final VoidCallback onTap;

  const _GameCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.emoji,
    required this.stats,
    required this.onTap,
  });

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: _isPressed
            ? (Matrix4.diagonal3Values(0.97, 0.97, 1.0))
            : Matrix4.identity(),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: widget.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.gradientColors.first.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
                    // Emoji grande
                    Text(widget.emoji, style: const TextStyle(fontSize: 40)),
                    const Spacer(),
                    // Icono con fondo translúcido
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.icon, size: 28, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Título
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                // Subtítulo
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                // Estadísticas y flecha
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.stats,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
