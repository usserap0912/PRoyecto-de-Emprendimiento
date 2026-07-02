import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/supabase_service.dart';

class PatrolGameScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const PatrolGameScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<PatrolGameScreen> createState() => _PatrolGameScreenState();
}

class _PatrolGameScreenState extends State<PatrolGameScreen>
    with SingleTickerProviderStateMixin {
  // Game constants
  static const int _numLanes = 4;
  static const double _playerBaseY = 0.82;
  static const double _spawnIntervalBase = 600; // ms between spawns

  // Game state
  int _currentLane = 1; // 0-3
  int _score = 0;
  int _shieldsCollected = 0;
  double _gameSpeed = 1.0;
  bool _isGameOver = false;
  bool _isPlaying = false;
  bool _showIntro = true;

  // Game objects
  final List<_Obstacle> _obstacles = [];
  final List<_Shield> _shields = [];
  final List<_Explosion> _explosions = [];

  // Controllers
  late AnimationController _gameController;
  Timer? _spawnTimer;
  final Random _random = Random();
  final SupabaseService _supabase = SupabaseService();

  // Swipe detection
  double _startDx = 0;

  @override
  void initState() {
    super.initState();
    _gameController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    _gameController.addListener(_gameLoop);
  }

  @override
  void dispose() {
    _gameController.stop();
    _gameController.removeListener(_gameLoop);
    _gameController.dispose();
    _spawnTimer?.cancel();
    super.dispose();
  }

  void _startGame() {
    setState(() {
      _showIntro = false;
      _isPlaying = true;
      _isGameOver = false;
      _score = 0;
      _shieldsCollected = 0;
      _gameSpeed = 1.0;
      _currentLane = 1;
      _obstacles.clear();
      _shields.clear();
      _explosions.clear();
    });
    _gameController.reset();
    _gameController.repeat();
    _startSpawning();
  }

  void _startSpawning() {
    _spawnTimer?.cancel();
    _scheduleSpawn();
  }

  void _scheduleSpawn() {
    if (_isGameOver || !mounted) return;
    final delay = (_spawnIntervalBase / _gameSpeed).toInt();
    _spawnTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      if (!_isGameOver) {
        _spawnObject();
        _scheduleSpawn();
      }
    });
  }

  void _spawnObject() {
    final lane = _random.nextInt(_numLanes);
    final isShield = _random.nextDouble() < 0.3; // 30% chance for shield

    if (isShield) {
      _shields.add(_Shield(lane: lane, y: -0.1));
    } else {
      final dangerTypes = ['🔴', '⚡', '🔥', '💀', '⚠️'];
      _obstacles.add(_Obstacle(
        lane: lane,
        y: -0.1,
        dangerType: dangerTypes[_random.nextInt(dangerTypes.length)],
      ));
    }
  }

  void _gameLoop() {
    if (_isGameOver || !_isPlaying || !mounted) return;

    // Speed up over time
    _gameSpeed = 1.0 + (_gameController.value * 60 * 0.005);

    // Update obstacles
    final delta = 0.008 * _gameSpeed;
    for (final obs in _obstacles) {
      obs.y += delta;
    }
    _obstacles.removeWhere((obs) => obs.y > 1.2);

    // Update shields
    for (final shield in _shields) {
      shield.y += delta;
    }
    _shields.removeWhere((s) => s.y > 1.2);

    // Update explosions
    for (final exp in _explosions) {
      exp.timer += 1;
    }
    _explosions.removeWhere((e) => e.timer > 20);

    // Collision detection: obstacles
    final playerY = _playerBaseY;
    for (final obs in _obstacles) {
      if (obs.y > playerY - 0.08 && obs.y < playerY + 0.08) {
        if (obs.lane == _currentLane) {
          _gameOver();
          return;
        }
      }
    }

    // Collision detection: shields
    for (final shield in _shields.toList()) {
      if (shield.y > playerY - 0.08 && shield.y < playerY + 0.08) {
        if (shield.lane == _currentLane) {
          _shields.remove(shield);
          _shieldsCollected++;
          _score += 50;
          _explosions.add(_Explosion(lane: shield.lane, y: playerY));
        }
      }
    }

    // Score based on survival
    _score += 1;

    if (mounted) setState(() {});
  }

  void _gameOver() {
    _isGameOver = true;
    _isPlaying = false;
    _gameController.stop();
    _spawnTimer?.cancel();

    // Add explosion at player position
    _explosions.add(_Explosion(lane: _currentLane, y: _playerBaseY));

    _saveScore();

    if (mounted) setState(() {});
  }

  Future<void> _saveScore() async {
    try {
      await _supabase.client.from('user_scores').insert({
        'user_code': widget.userCode,
        'game_type': 'patrol',
        'score': _score,
      });
    } catch (e) {
      debugPrint('Error saving patrol score: $e');
    }
  }

  void _moveLeft() {
    if (!_isPlaying || _isGameOver) return;
    setState(() {
      _currentLane = (_currentLane - 1).clamp(0, _numLanes - 1);
    });
  }

  void _moveRight() {
    if (!_isPlaying || _isGameOver) return;
    setState(() {
      _currentLane = (_currentLane + 1).clamp(0, _numLanes - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showIntro
              ? 'Patrullaje'
              : _isGameOver
                  ? 'Patrullaje'
                  : 'Patrullaje',
        ),
        centerTitle: true,
        actions: [
          if (!_showIntro && !_isGameOver)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stars, size: 16, color: AppTheme.warningYellow),
                    const SizedBox(width: 4),
                    Text(
                      '$_score',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _showIntro
            ? _buildIntro(isDark)
            : _isGameOver
                ? _buildGameOver(isDark)
                : _buildGameArea(isDark),
      ),
    );
  }

  Widget _buildIntro(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.safeGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car,
                size: 50,
                color: AppTheme.safeGreen,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Patrullaje de la Revolución',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInstructionRow(Icons.swipe, 'Desliza o toca para cambiar de carril', textColor),
                  const SizedBox(height: 10),
                  _buildInstructionRow(Icons.shield, 'Recoge los escudos 🛡️ (+50 pts)', AppTheme.safeGreen),
                  const SizedBox(height: 10),
                  _buildInstructionRow(Icons.dangerous, 'Esquiva los peligros 🔴⚡🔥', AppTheme.dangerRed),
                  const SizedBox(height: 10),
                  _buildInstructionRow(Icons.speed, 'La velocidad aumenta con el tiempo', AppTheme.warningYellow),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _startGame,
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text(
                  'COMENZAR PATRULLAJE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.safeGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
      ],
    );
  }

  Widget _buildGameArea(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final laneW = constraints.maxWidth / _numLanes;
        final playerX = _currentLane * laneW + laneW / 2;
        final playerY = constraints.maxHeight * _playerBaseY;

        return GestureDetector(
          onHorizontalDragStart: (details) {
            _startDx = details.localPosition.dx;
          },
          onHorizontalDragEnd: (details) {
            final dx = details.localPosition.dx - _startDx;
            if (dx < -30) {
              _moveRight();
            } else if (dx > 30) {
              _moveLeft();
            }
          },
          onTapUp: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            if (details.localPosition.dx < screenWidth / 2) {
              _moveLeft();
            } else {
              _moveRight();
            }
          },
          child: Stack(
            children: [
              // Background
              _buildGameBackground(constraints, isDark),
              // Lane markers
              ...List.generate(_numLanes + 1, (i) {
                return Positioned(
                  left: i * laneW - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                );
              }),
              // Road markings (dashed center lines)
              ...List.generate(_numLanes, (i) {
                if (i == 0) return const SizedBox.shrink();
                final x = i * laneW;
                return Positioned(
                  left: x - 0.5,
                  top: 0,
                  bottom: 0,
                  child: CustomPaint(
                    size: Size(1, constraints.maxHeight),
                    painter: _DashedLinePainter(isDark: isDark),
                  ),
                );
              }),
              // Obstacles
              ..._obstacles.map((obs) {
                final ox = obs.lane * laneW + laneW / 2;
                final oy = obs.y * constraints.maxHeight;
                return Positioned(
                  left: ox - 18,
                  top: oy - 18,
                  child: _DangerWidget(dangerType: obs.dangerType),
                );
              }),
              // Shields
              ..._shields.map((shield) {
                final sx = shield.lane * laneW + laneW / 2;
                final sy = shield.y * constraints.maxHeight;
                return Positioned(
                  left: sx - 16,
                  top: sy - 16,
                  child: _ShieldWidget(),
                );
              }),
              // Explosions
              ..._explosions.map((exp) {
                final ex = exp.lane * laneW + laneW / 2;
                final ey = exp.y * constraints.maxHeight;
                return Positioned(
                  left: ex - 24,
                  top: ey - 24,
                  child: Opacity(
                    opacity: (1.0 - exp.timer / 20.0).clamp(0, 1),
                    child: Transform.scale(
                      scale: 1.0 + (exp.timer / 20.0),
                      child: const Text('💥', style: TextStyle(fontSize: 40)),
                    ),
                  ),
                );
              }),
              // Player car
              Positioned(
                left: playerX - 22,
                top: playerY - 22,
                child: _buildPlayer(isDark),
              ),
              // HUD info
              Positioned(
                top: 8,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, size: 14, color: AppTheme.safeGreen),
                      const SizedBox(width: 4),
                      Text(
                        '${(_gameSpeed * 30).toInt()} km/h',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Shield counter
              Positioned(
                top: 8,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🛡️', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        '$_shieldsCollected',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.safeGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Touch controls hint
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ControlButton(
                      icon: Icons.chevron_left,
                      onTap: _moveLeft,
                      label: '← Tocar',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 40),
                    Text(
                      'o desliza',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(width: 40),
                    _ControlButton(
                      icon: Icons.chevron_right,
                      onTap: _moveRight,
                      label: 'Tocar →',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGameBackground(BoxConstraints constraints, bool isDark) {
    return Container(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  const Color(0xFF1A1A2E),
                  const Color(0xFF2D1B2E),
                  const Color(0xFF1A1A2E),
                ]
              : [
                  const Color(0xFFB8C6DB),
                  const Color(0xFF8BA3C7),
                  const Color(0xFF6B8BAE),
                ],
        ),
      ),
      child: Stack(
        children: [
          // Road surface
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(
              color: isDark
                  ? const Color(0xFF2A2A3E)
                  : const Color(0xFF7A9AAD),
            ),
          ),
          // Road side edges
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              color: isDark ? Colors.yellow.withValues(alpha: 0.3) : Colors.yellow.withValues(alpha: 0.5),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              color: isDark ? Colors.yellow.withValues(alpha: 0.3) : Colors.yellow.withValues(alpha: 0.5),
            ),
          ),
          // Scrolling road effect (moving dashes)
          ...List.generate(8, (i) {
            final phase = (_gameController.value * 60 * 6.0 * _gameSpeed + i * 60) % 480;
            return Positioned(
              left: _numLanes * (constraints.maxWidth / _numLanes) / 2 - 1,
              top: phase - 480 + 30,
              child: Container(
                width: 3,
                height: 30,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.4),
              ),
            );
          }),
          // Side decorations
          Positioned(
            left: 6,
            top: 0,
            bottom: 0,
            child: Container(
              width: 8,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.safeGreen.withValues(alpha: 0.3),
                    AppTheme.safeGreen.withValues(alpha: 0.1),
                    AppTheme.safeGreen.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Container(
              width: 8,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.dangerRed.withValues(alpha: 0.3),
                    AppTheme.dangerRed.withValues(alpha: 0.1),
                    AppTheme.dangerRed.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer(bool isDark) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [AppTheme.primaryLight, AppTheme.primaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withValues(alpha: 0.5),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Icon(Icons.shield, color: Colors.white, size: 26),
    );
  }

  Widget _buildGameOver(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;

    // Determine rank
    String rank;
    Color rankColor;
    if (_score >= 5000) {
      rank = '🚓 ¡Super Patrullero!';
      rankColor = AppTheme.warningYellow;
    } else if (_score >= 2000) {
      rank = '👮 Patrullero de élite';
      rankColor = AppTheme.shieldBlue;
    } else if (_score >= 500) {
      rank = '🚶‍♂️ Vigilante vecinal';
      rankColor = AppTheme.safeGreen;
    } else {
      rank = '🐣 Novato';
      rankColor = Colors.grey;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💥', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'Patrullaje terminado',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              rank,
              style: TextStyle(fontSize: 18, color: rankColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            // Score card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildResultStat(Icons.stars, '$_score', 'Puntos', AppTheme.warningYellow),
                      _buildResultStat(Icons.shield, '$_shieldsCollected', 'Escudos', AppTheme.safeGreen),
                      _buildResultStat(
                        Icons.speed,
                        '${(_gameSpeed * 30).toInt()}',
                        'Km/h máx',
                        AppTheme.dangerRed,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _startGame,
                icon: const Icon(Icons.replay, size: 22),
                label: const Text(
                  'PATRULLAR DE NUEVO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.safeGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _showIntro = true),
              child: const Text(
                'Volver a instrucciones',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultStat(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}

/// ============================================================
/// Game model classes
/// ============================================================
class _Obstacle {
  final int lane;
  double y;
  final String dangerType;

  _Obstacle({required this.lane, required this.y, required this.dangerType});
}

class _Shield {
  final int lane;
  double y;

  _Shield({required this.lane, required this.y});
}

class _Explosion {
  final int lane;
  final double y;
  double timer = 0;

  _Explosion({required this.lane, required this.y});
}

/// Danger emoji widget with glow
class _DangerWidget extends StatelessWidget {
  final String dangerType;

  const _DangerWidget({required this.dangerType});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(dangerType, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}

/// Shield collectible widget
class _ShieldWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppTheme.safeGreen.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.safeGreen.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Center(
        child: Text('🛡️', style: TextStyle(fontSize: 18)),
      ),
    );
  }
}

/// Control button
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final bool isDark;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isDark ? Colors.white70 : Colors.black54),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed line painter for lane markings
class _DashedLinePainter extends CustomPainter {
  final bool isDark;

  _DashedLinePainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.15)
          : Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1.5;

    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(0, y),
        Offset(0, (y + 20).clamp(0, size.height)),
        paint,
      );
      y += 50;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
