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
  static const int _numLanes = 4;
  static const double _playerBaseY = 0.82;
  static const double _spawnIntervalBase = 600;

  int _currentLane = 1;
  int _score = 0;
  int _shieldsCollected = 0;
  double _gameSpeed = 1.0;
  bool _isGameOver = false;
  bool _isPlaying = false;
  bool _showIntro = true;

  final List<_Obstacle> _obstacles = [];
  final List<_Shield> _shields = [];
  final List<_Explosion> _explosions = [];
  final List<_Particle> _particles = [];
  final List<_SpeedLine> _speedLines = [];

  late AnimationController _gameController;
  Timer? _spawnTimer;
  final Random _random = Random();
  final SupabaseService _supabase = SupabaseService();
  double _startDx = 0;
  late final List<_BuildingData> _buildings;

  @override
  void initState() {
    super.initState();
    _buildings = List.generate(12, (i) => _BuildingData.generate(i, _random));
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
      _particles.clear();
      _speedLines.clear();
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
    final isShield = _random.nextDouble() < 0.3;

    if (isShield) {
      _shields.add(_Shield(lane: lane, y: -0.1));
    } else {
      final types = [_DangerType.cone, _DangerType.fire, _DangerType.spike, _DangerType.skull];
      _obstacles.add(_Obstacle(
        lane: lane,
        y: -0.1,
        dangerType: types[_random.nextInt(types.length)],
      ));
    }
  }

  void _gameLoop() {
    if (_isGameOver || !_isPlaying || !mounted) return;

    _gameSpeed = 1.0 + (_gameController.value * 60 * 0.005);
    final delta = 0.008 * _gameSpeed;

    // Speed lines
    if (_random.nextDouble() < 0.3) {
      _speedLines.add(_SpeedLine(
        x: _random.nextDouble(),
        speed: 1.0 + _random.nextDouble() * 0.5,
      ));
    }
    for (final line in _speedLines) {
      line.progress += 0.03 * _gameSpeed;
    }
    _speedLines.removeWhere((l) => l.progress > 1.0);

    // Obstacles
    for (final obs in _obstacles) {
      obs.y += delta;
    }
    _obstacles.removeWhere((obs) => obs.y > 1.2);

    // Shields
    for (final shield in _shields) {
      shield.y += delta;
    }
    _shields.removeWhere((s) => s.y > 1.2);

    // Explosions
    for (final exp in _explosions) {
      exp.timer += 1;
    }
    _explosions.removeWhere((e) => e.timer > 20);

    // Particles
    for (final p in _particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.002;
      p.life -= 0.02;
    }
    _particles.removeWhere((p) => p.life <= 0);

    // Collision obstacles
    final playerY = _playerBaseY;
    for (final obs in _obstacles) {
      if (obs.y > playerY - 0.08 && obs.y < playerY + 0.08) {
        if (obs.lane == _currentLane) {
          _spawnExplosionParticles(_currentLane, playerY);
          _gameOver();
          return;
        }
      }
    }

    // Collision shields
    for (final shield in _shields.toList()) {
      if (shield.y > playerY - 0.08 && shield.y < playerY + 0.08) {
        if (shield.lane == _currentLane) {
          _shields.remove(shield);
          _shieldsCollected++;
          _score += 50;
          _spawnCollectParticles(shield.lane, playerY);
        }
      }
    }

    _score += 1;
    if (mounted) setState(() {});
  }

  void _spawnExplosionParticles(int lane, double y) {
    for (int i = 0; i < 15; i++) {
      _particles.add(_Particle(
        x: (lane + 0.5) / _numLanes,
        y: y,
        vx: (_random.nextDouble() - 0.5) * 0.03,
        vy: -_random.nextDouble() * 0.03,
        life: 1.0,
        color: _random.nextBool() ? Colors.red : Colors.orange,
      ));
    }
  }

  void _spawnCollectParticles(int lane, double y) {
    for (int i = 0; i < 8; i++) {
      _particles.add(_Particle(
        x: (lane + 0.5) / _numLanes,
        y: y,
        vx: (_random.nextDouble() - 0.5) * 0.02,
        vy: -_random.nextDouble() * 0.03,
        life: 1.0,
        color: AppTheme.safeGreen,
      ));
    }
  }

  void _gameOver() {
    _isGameOver = true;
    _isPlaying = false;
    _gameController.stop();
    _spawnTimer?.cancel();
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
    setState(() => _currentLane = (_currentLane - 1).clamp(0, _numLanes - 1));
  }

  void _moveRight() {
    if (!_isPlaying || _isGameOver) return;
    setState(() => _currentLane = (_currentLane + 1).clamp(0, _numLanes - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showIntro ? 'Patrullaje' : _isGameOver ? 'Patrullaje' : 'Patrullaje'),
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
                        color: Colors.white,
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
            ? _buildIntro()
            : _isGameOver
                ? _buildGameOver()
                : _buildGameArea(),
      ),
    );
  }

  // ============================================================
  // INTRO MEJORADA
  // ============================================================
  Widget _buildIntro() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo patrol
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryGreen, AppTheme.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(Icons.local_police_rounded, size: 60, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                'Patrullaje de\nla Revolución',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.3,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Av. Revolución - Collique',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInstructionRow(Icons.swipe_rounded, 'Desliza o toca para cambiar de carril', Colors.white70),
                    const SizedBox(height: 12),
                    _buildInstructionRow(Icons.shield, 'Recoge los escudos 🛡️ (+50 pts)', AppTheme.safeGreen),
                    const SizedBox(height: 12),
                    _buildInstructionRow(Icons.dangerous_outlined, 'Esquiva los peligros 🔴⚡🔥', AppTheme.dangerRed),
                    const SizedBox(height: 12),
                    _buildInstructionRow(Icons.speed, 'La velocidad aumenta con el tiempo ⏱️', AppTheme.warningYellow),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _startGame,
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text(
                    'COMENZAR PATRULLAJE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.safeGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 8,
                    shadowColor: AppTheme.safeGreen.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    );
  }

  // ============================================================
  // GAME AREA MEJORADO
  // ============================================================
  Widget _buildGameArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final laneW = constraints.maxWidth / _numLanes;
        final playerX = _currentLane * laneW + laneW / 2;
        final playerY = constraints.maxHeight * _playerBaseY;

        return GestureDetector(
          onHorizontalDragStart: (details) => _startDx = details.localPosition.dx,
          onHorizontalDragEnd: (details) {
            final dx = details.localPosition.dx - _startDx;
            if (dx < -30) {
              _moveRight();
            } else if (dx > 30) {
              _moveLeft();
            }
          },
          onTapUp: (details) {
            if (details.localPosition.dx < MediaQuery.of(context).size.width / 2) {
              _moveLeft();
            } else {
              _moveRight();
            }
          },
          child: Stack(
            children: [
              _buildGameBackground(constraints),
              // Lane markers
              ...List.generate(_numLanes + 1, (i) {
                return Positioned(
                  left: i * laneW - 1, top: 0, bottom: 0,
                  child: Container(
                    width: 2,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                );
              }),
              // Dashed center lines
              ...List.generate(_numLanes, (i) {
                if (i == 0) return const SizedBox.shrink();
                return Positioned(
                  left: i * laneW - 0.5, top: 0, bottom: 0,
                  child: CustomPaint(
                    size: Size(1, constraints.maxHeight),
                    painter: _DashedLinePainter(),
                  ),
                );
              }),
              // Speed lines
              ..._speedLines.map((line) {
                return Positioned(
                  left: line.x * constraints.maxWidth,
                  top: 0,
                  child: AnimatedBuilder(
                    animation: _gameController,
                    builder: (context, _) {
                      return Container(
                        width: 2,
                        height: 60 + line.speed * 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: 0.15 * line.speed),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
              // Obstacles
              ..._obstacles.map((obs) {
                final ox = obs.lane * laneW + laneW / 2;
                final oy = obs.y * constraints.maxHeight;
                return Positioned(
                  left: ox - 20, top: oy - 20,
                  child: _DangerWidget(dangerType: obs.dangerType),
                );
              }),
              // Shields
              ..._shields.map((shield) {
                final sx = shield.lane * laneW + laneW / 2;
                final sy = shield.y * constraints.maxHeight;
                return Positioned(
                  left: sx - 18, top: sy - 18,
                  child: _ShieldWidget(),
                );
              }),
              // Particles
              ..._particles.map((p) {
                return Positioned(
                  left: p.x * constraints.maxWidth,
                  top: p.y * constraints.maxHeight,
                  child: Opacity(
                    opacity: p.life.clamp(0, 1),
                    child: Container(
                      width: 4 + p.life * 4,
                      height: 4 + p.life * 4,
                      decoration: BoxDecoration(
                        color: p.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
              // Explosions
              ..._explosions.map((exp) {
                final ex = exp.lane * laneW + laneW / 2;
                final ey = exp.y * constraints.maxHeight;
                return Positioned(
                  left: ex - 30, top: ey - 30,
                  child: Opacity(
                    opacity: (1.0 - exp.timer / 20.0).clamp(0, 1),
                    child: Transform.scale(
                      scale: 1.0 + (exp.timer / 20.0),
                      child: const Text('💥', style: TextStyle(fontSize: 50)),
                    ),
                  ),
                );
              }),
              // Player - AUTO MEJORADO
              Positioned(
                left: playerX - 24, top: playerY - 24,
                child: _buildPlayerCar(),
              ),
              // HUD
              Positioned(
                top: 8, left: 12,
                child: _buildHudChip(
                  icon: Icons.speed,
                  value: '${(_gameSpeed * 30).toInt()} km/h',
                  color: AppTheme.safeGreen,
                ),
              ),
              Positioned(
                top: 8, right: 12,
                child: _buildHudChip(
                  icon: Icons.shield,
                  value: '$_shieldsCollected',
                  color: AppTheme.shieldBlue,
                ),
              ),
              // Score HUD
              Positioned(
                top: 46, right: 12,
                child: _buildHudChip(
                  icon: Icons.stars,
                  value: '$_score pts',
                  color: AppTheme.warningYellow,
                ),
              ),
              // Controls
              Positioned(
                bottom: 12, left: 0, right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ControlButton(
                      icon: Icons.chevron_left,
                      onTap: _moveLeft,
                      label: '← Izquierda',
                    ),
                    const SizedBox(width: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'o desliza',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    _ControlButton(
                      icon: Icons.chevron_right,
                      onTap: _moveRight,
                      label: 'Derecha →',
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

  Widget _buildHudChip({required IconData icon, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FONDO MEJORADO - CON EDIFICIOS Y CIUDAD
  // ============================================================
  Widget _buildGameBackground(BoxConstraints constraints) {
    return Container(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F0C29),
            Color(0xFF302B63),
            Color(0xFF24243E),
          ],
        ),
      ),
      child: Stack(
        children: [
          // City skyline buildings (pre-generados para evitar flickering)
          ..._buildings.map((b) {
            final x = b.index * (constraints.maxWidth / 12);
            return Positioned(
              left: x,
              bottom: constraints.maxHeight * 0.55,
              child: Container(
                width: b.width,
                height: b.height,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A3E).withValues(alpha: 0.6),
                  border: Border.all(
                    color: const Color(0xFF2A2A5E).withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: b.hasWindows
                    ? Column(
                        children: List.generate(3, (j) {
                          return Expanded(
                            child: Row(
                              children: List.generate(2, (k) {
                                final idx = (j * 2 + k) % b.windowLights.length;
                                final lit = b.windowLights[idx];
                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.all(1),
                                    decoration: BoxDecoration(
                                      color: lit
                                          ? const Color(0xFFFFD700).withValues(alpha: 0.3)
                                          : const Color(0xFF1A1A3E).withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(0.5),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        }),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }),
          // Road surface
          Positioned(
            left: 0, right: 0,
            bottom: 0,
            height: constraints.maxHeight * 0.55,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2A2A3E),
                    Color(0xFF1E1E32),
                    Color(0xFF181828),
                  ],
                ),
              ),
            ),
          ),
          // Road edges with glow effect
          Positioned(left: 0, top: 0, bottom: 0,
            child: Container(
              width: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.safeGreen.withValues(alpha: 0.2),
                    AppTheme.safeGreen.withValues(alpha: 0.1),
                    AppTheme.safeGreen.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
          Positioned(right: 0, top: 0, bottom: 0,
            child: Container(
              width: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.dangerRed.withValues(alpha: 0.2),
                    AppTheme.dangerRed.withValues(alpha: 0.1),
                    AppTheme.dangerRed.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
          // Street lights effect
          ...List.generate(6, (i) {
            final x = i * (constraints.maxWidth / 6) + 20;
            return Positioned(
              left: x,
              top: constraints.maxHeight * 0.52,
              child: Container(
                width: 3,
                height: 20,
                color: AppTheme.warningYellow.withValues(alpha: 0.15),
              ),
            );
          }),
          // Scrolling road dashes
          ...List.generate(8, (i) {
            final phase = (_gameController.value * 60 * 6.0 * _gameSpeed + i * 60) % 480;
            return Positioned(
              left: _numLanes * (constraints.maxWidth / _numLanes) / 2 - 2,
              top: phase - 480 + 30,
              child: Container(
                width: 4,
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.2),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ============================================================
  // AUTO DEL JUGADOR - MEJORADO
  // ============================================================
  Widget _buildPlayerCar() {
    return AnimatedBuilder(
      animation: _gameController,
      builder: (context, _) {
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [AppTheme.primaryLight, AppTheme.primaryGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withValues(alpha: 0.6),
                blurRadius: 16,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: AppTheme.primaryLight.withValues(alpha: 0.3),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Sirena lights
              Positioned(
                top: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: (_gameController.value * 4).floor() % 2 == 0
                            ? Colors.red : Colors.red.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: (_gameController.value * 4).floor() % 2 == 1
                            ? Colors.blue : Colors.blue.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              // Icon
              const Icon(Icons.local_police_rounded, color: Colors.white, size: 28),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // GAME OVER MEJORADO
  // ============================================================
  Widget _buildGameOver() {
    String rank;
    Color rankColor;
    IconData rankIcon;
    if (_score >= 5000) {
      rank = '🚓 ¡Super Patrullero!';
      rankColor = AppTheme.warningYellow;
      rankIcon = Icons.emoji_events;
    } else if (_score >= 2000) {
      rank = '👮 Patrullero de élite';
      rankColor = AppTheme.shieldBlue;
      rankIcon = Icons.verified;
    } else if (_score >= 500) {
      rank = '🚶 Vigilante vecinal';
      rankColor = AppTheme.safeGreen;
      rankIcon = Icons.shield;
    } else {
      rank = '🐣 Novato';
      rankColor = Colors.grey;
      rankIcon = Icons.pets;
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💥', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 16),
              const Text(
                'Patrullaje terminado',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [rankColor.withValues(alpha: 0.2), rankColor.withValues(alpha: 0.05)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: rankColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(rankIcon, color: rankColor, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      rank,
                      style: TextStyle(fontSize: 18, color: rankColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResultStat(Icons.stars, '$_score', 'Puntos', AppTheme.warningYellow),
                    _buildResultStat(Icons.shield, '$_shieldsCollected', 'Escudos', AppTheme.safeGreen),
                    _buildResultStat(Icons.speed, '${(_gameSpeed * 30).toInt()}', 'Km/h máx', AppTheme.dangerRed),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _startGame,
                  icon: const Icon(Icons.replay, size: 22),
                  label: const Text(
                    'PATRULLAR DE NUEVO',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.safeGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 8,
                    shadowColor: AppTheme.safeGreen.withValues(alpha: 0.5),
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
      ),
    );
  }

  Widget _buildResultStat(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

// ============================================================
// MODELOS Y WIDGETS
// ============================================================
class _BuildingData {
  final int index;
  final double width;
  final double height;
  final bool hasWindows;
  final List<bool> windowLights;

  _BuildingData({
    required this.index,
    required this.width,
    required this.height,
    required this.hasWindows,
    required this.windowLights,
  });

  factory _BuildingData.generate(int index, Random random) {
    final h = 40 + random.nextInt(80);
    final w = 20 + random.nextInt(30);
    final ws = random.nextBool();
    final lights = List.generate(6, (_) => random.nextDouble() > 0.4);
    return _BuildingData(
      index: index,
      width: w.toDouble(),
      height: h.toDouble(),
      hasWindows: ws,
      windowLights: lights,
    );
  }
}

enum _DangerType { cone, fire, spike, skull }

class _Obstacle {
  final int lane;
  double y;
  final _DangerType dangerType;
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

class _Particle {
  double x, y, vx, vy, life;
  final Color color;
  _Particle({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.life, required this.color,
  });
}

class _SpeedLine {
  final double x;
  double progress = 0;
  final double speed;
  _SpeedLine({required this.x, required this.speed});
}

// ============================================================
// OBSTÁCULOS MEJORADOS VISUALMENTE
// ============================================================
class _DangerWidget extends StatelessWidget {
  final _DangerType dangerType;
  const _DangerWidget({required this.dangerType});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (dangerType) {
      case _DangerType.cone:
        icon = Icons.warning_amber_rounded;
        color = AppTheme.alertOrange;
      case _DangerType.fire:
        icon = Icons.local_fire_department;
        color = Colors.red;
      case _DangerType.spike:
        icon = Icons.dangerous;
        color = Colors.purple;
      case _DangerType.skull:
        icon = Icons.gpp_bad;
        color = Colors.grey;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

// ============================================================
// ESCUDO MEJORADO
// ============================================================
class _ShieldWidget extends StatefulWidget {
  @override
  State<_ShieldWidget> createState() => _ShieldWidgetState();
}

class _ShieldWidgetState extends State<_ShieldWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
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
      builder: (context, _) {
        final scale = 0.8 + _pulseController.value * 0.4;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.safeGreen.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.safeGreen.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.safeGreen.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.shield, color: AppTheme.safeGreen, size: 20),
          ),
        );
      },
    );
  }
}

// ============================================================
// CONTROLES MEJORADOS
// ============================================================
class _ControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.label,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: _pressed ? Matrix4.diagonal3Values(0.9, 0.9, 1) : Matrix4.identity(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: _pressed ? 0.25 : 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 20, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: _pressed ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DASHED LINE PAINTER
// ============================================================
class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 2;

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
