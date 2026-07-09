import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/supabase_service.dart';

class TriviaGameScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const TriviaGameScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<TriviaGameScreen> createState() => _TriviaGameScreenState();
}

class _TriviaGameScreenState extends State<TriviaGameScreen>
    with TickerProviderStateMixin {
  int _currentQuestion = 0;
  int _score = 0;
  int _lives = 3;
  int _streak = 0;
  int _timeLeft = 15;
  Timer? _timer;
  bool _isAnswered = false;
  int? _selectedIndex;
  bool _isCorrect = false;
  late AnimationController _feedbackController;
  late Animation<double> _feedbackAnim;
  late AnimationController _questionSlideController;
  String? _feedbackMessage;
  bool _gameOver = false;
  bool _gameWon = false;

  // Confetti
  final List<_ConfettiParticle> _confetti = [];
  late AnimationController _confettiController;
  final Random _random = Random();

  final SupabaseService _supabase = SupabaseService();

  final List<TriviaQuestion> _questions = [
    TriviaQuestion(
      question: '¿Cuál es el número de emergencia de la Policía Nacional del Perú?',
      options: ['105', '106', '107', '116'],
      correctIndex: 0,
      explanation: 'El 105 es el número de la Policía Nacional. El 106 es para emergencias médicas (SAMU).',
      category: 'Emergencias',
    ),
    TriviaQuestion(
      question: '¿Qué zona de Collique limita con las Lomas de Collique?',
      options: ['1ra Zona', '3ra Zona', '5ta Zona', 'Av. Revolución'],
      correctIndex: 2,
      explanation: 'La 5ta Zona de Collique se encuentra en las partes altas, colindando con las Lomas de Collique.',
      category: 'Geografía',
    ),
    TriviaQuestion(
      question: '¿Cuál es el número del SAMU (emergencias médicas)?',
      options: ['105', '106', '107', '116'],
      correctIndex: 1,
      explanation: 'El SAMU se marca marcando el 106 para emergencias médicas.',
      category: 'Emergencias',
    ),
    TriviaQuestion(
      question: '¿Qué avenida principal atraviesa Collique?',
      options: ['Av. Túpac Amaru', 'Av. Revolución', 'Av. Collique', 'Av. Universitaria'],
      correctIndex: 1,
      explanation: 'La Av. Revolución es la vía principal que atraviesa las zonas de Collique.',
      category: 'Geografía',
    ),
    TriviaQuestion(
      question: '¿Qué hacer si ves un comportamiento sospechoso en tu vecindario?',
      options: [
        'Ignorarlo y seguir tu camino',
        'Reportarlo en SafeZone y llamar al 105',
        'Publicarlo en redes sociales',
        'Confrontar a la persona',
      ],
      correctIndex: 1,
      explanation: 'Lo más seguro es reportar en SafeZone y, si es urgente, llamar al 105.',
      category: 'Seguridad',
    ),
    TriviaQuestion(
      question: '¿En qué distrito se encuentra Collique?',
      options: ['Los Olivos', 'Comas', 'Independencia', 'Carabayllo'],
      correctIndex: 1,
      explanation: 'Collique es un sector del distrito de Comas, en Lima Norte.',
      category: 'Geografía',
    ),
    TriviaQuestion(
      question: '¿Qué hospital da servicio a la zona de Collique?',
      options: ['Hospital Cayetano Heredia', 'Hospital Sergio Bernales', 'Hospital Loayza', 'Hospital Almenara'],
      correctIndex: 1,
      explanation: 'El Hospital Sergio Bernales, ubicado en Collique, es el principal centro de salud de la zona.',
      category: 'Salud',
    ),
    TriviaQuestion(
      question: '¿Cuál es el número de emergencia nacional para bomberos?',
      options: ['105', '106', '107', '116'],
      correctIndex: 3,
      explanation: 'El 116 es el número de los Bomberos del Perú a nivel nacional.',
      category: 'Emergencias',
    ),
    TriviaQuestion(
      question: '¿Qué cultura prehispánica habitó la zona de Collique?',
      options: ['Los Incas', 'Los Colli', 'Los Moche', 'Los Nazca'],
      correctIndex: 1,
      explanation: 'La Cultura Colli habitó esta zona. Su fortaleza y museo son parte importante de Collique.',
      category: 'Historia',
    ),
    TriviaQuestion(
      question: '¿Cuál es la mejor acción al recibir una alerta S.O.S. en SafeZone?',
      options: [
        'Ignorarla si no conoces a la persona',
        'Revisar la ubicación y estar atento para ayudar si es seguro',
        'Publicarla en redes sociales',
        'Llamar a todos tus contactos',
      ],
      correctIndex: 1,
      explanation: 'Revisar la ubicación y estar alerta puede ayudar a tu vecino sin ponerte en riesgo innecesario.',
      category: 'Seguridad',
    ),
    TriviaQuestion(
      question: '¿Qué significa la etiqueta ROJA en un reporte de SafeZone?',
      options: ['Peligro inminente', 'Precaución', 'Resuelto', 'Información general'],
      correctIndex: 0,
      explanation: 'La etiqueta ROJA indica un peligro inminente que requiere atención inmediata.',
      category: 'Seguridad',
    ),
    TriviaQuestion(
      question: '¿Qué zona de Collique es conocida por su mercado principal?',
      options: ['1ra Zona', '2da Zona', '3ra Zona', '4ta Zona'],
      correctIndex: 1,
      explanation: 'La 2da Zona de Collique alberga el mercado principal y la zona comercial más activa.',
      category: 'Geografía',
    ),
    TriviaQuestion(
      question: '¿Para qué sirve la función "Walk With Me" en SafeZone?',
      options: [
        'Para hacer ejercicio',
        'Para compartir tu ubicación en tiempo real con un contacto de confianza',
        'Para caminar con tu mascota',
        'Para buscar restaurantes cercanos',
      ],
      correctIndex: 1,
      explanation: '"Walk With Me" permite compartir tu ubicación en tiempo real para que alguien de confianza pueda seguir tu trayecto seguro.',
      category: 'Seguridad',
    ),
    TriviaQuestion(
      question: '¿Cómo se llama el sitio arqueológico ubicado en Collique?',
      options: ['Huaca Pucllana', 'Fortaleza de Collique', 'Pachacámac', 'Caral'],
      correctIndex: 1,
      explanation: 'La Fortaleza de Collique, hoy Museo de los Colli, es el principal sitio arqueológico de la zona.',
      category: 'Historia',
    ),
    TriviaQuestion(
      question: 'Si te encuentras en una emergencia sin saldo en tu celular, ¿puedes llamar al 105?',
      options: [
        'Sí, las llamadas de emergencia son gratuitas siempre',
        'No, necesitas saldo obligatoriamente',
        'Solo si tienes WiFi',
        'Depende del operador',
      ],
      correctIndex: 0,
      explanation: 'Las llamadas a números de emergencia (105, 106, 107, 116) son gratuitas desde cualquier teléfono, incluso sin saldo o con línea bloqueada.',
      category: 'Emergencias',
    ),
  ];

  bool get _isLastQuestion => _currentQuestion >= _questions.length - 1;

  @override
  void initState() {
    super.initState();
    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _feedbackAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _feedbackController, curve: Curves.easeOutBack),
    );
    _questionSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _shuffleQuestions();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _feedbackController.dispose();
    _questionSlideController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _shuffleQuestions() => _questions.shuffle();

  void _startTimer() {
    _timer?.cancel();
    if (_gameOver || _gameWon) return;
    setState(() => _timeLeft = 15);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_timeLeft <= 1) {
        timer.cancel();
        if (!_isAnswered) _handleTimeout();
      } else {
        setState(() => _timeLeft--);
      }
    });
  }

  void _handleTimeout() {
    if (!mounted) return;
    setState(() {
      _isAnswered = true;
      _selectedIndex = -1;
      _isCorrect = false;
      _lives--;
      _streak = 0;
      _feedbackMessage = '⏰ ¡Se acabó el tiempo!';
    });
    _feedbackController.forward(from: 0);
    _timer?.cancel();
    _checkGameOver();
  }

  void _selectAnswer(int index) {
    if (_isAnswered) return;
    _timer?.cancel();

    setState(() {
      _isAnswered = true;
      _selectedIndex = index;
      _isCorrect = index == _questions[_currentQuestion].correctIndex;
      _feedbackMessage = _isCorrect ? '✅ ¡Correcto!' : '❌ Incorrecto';
    });

    if (_isCorrect) {
      final timeBonus = _timeLeft;
      final streakBonus = (_streak >= 2 ? _streak * 5 : 0);
      setState(() {
        _score += 10 + timeBonus + streakBonus;
        _streak++;
      });
      _spawnConfetti();
    } else {
      setState(() {
        _lives--;
        _streak = 0;
      });
    }

    _feedbackController.forward(from: 0);
    _checkGameOver();
  }

  void _spawnConfetti() {
    _confetti.clear();
    for (int i = 0; i < 30; i++) {
      _confetti.add(_ConfettiParticle(
        x: _random.nextDouble(),
        y: -0.1,
        vx: (_random.nextDouble() - 0.5) * 0.02,
        vy: 0.01 + _random.nextDouble() * 0.02,
        color: [
          AppTheme.warningYellow,
          AppTheme.safeGreen,
          AppTheme.shieldBlue,
          AppTheme.primaryLight,
          Colors.purple,
        ][_random.nextInt(5)],
        size: 4 + _random.nextDouble() * 6,
        rotation: _random.nextDouble() * 6.28,
      ));
    }
    _confettiController.forward(from: 0);
  }

  void _checkGameOver() {
    if (_lives <= 0) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        setState(() => _gameOver = true);
        _saveScore();
      });
    } else if (_isLastQuestion && _isAnswered) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        setState(() => _gameWon = true);
        _saveScore();
      });
    }
  }

  Future<void> _saveScore() async {
    try {
      await _supabase.client.from('user_scores').insert({
        'user_code': widget.userCode,
        'game_type': 'trivia',
        'score': _score,
      });
    } catch (e) {
      debugPrint('Error saving trivia score: $e');
    }
  }

  void _nextQuestion() {
    if (_isLastQuestion) return;
    setState(() {
      _currentQuestion++;
      _isAnswered = false;
      _selectedIndex = null;
      _isCorrect = false;
      _feedbackMessage = null;
    });
    _feedbackController.reset();
    _questionSlideController.forward(from: 0);
    _startTimer();
  }

  void _restartGame() {
    _shuffleQuestions();
    setState(() {
      _currentQuestion = 0;
      _score = 0;
      _lives = 3;
      _streak = 0;
      _isAnswered = false;
      _selectedIndex = null;
      _isCorrect = false;
      _gameOver = false;
      _gameWon = false;
      _feedbackMessage = null;
    });
    _feedbackController.reset();
    _questionSlideController.reset();
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: Text(_gameOver || _gameWon ? 'Resultados' : 'Trivia de Seguridad'),
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
          if (!_gameOver && !_gameWon)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Pregunta ${_currentQuestion + 1}/${_questions.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                : [const Color(0xFFF5F5F5), const Color(0xFFE8EAF6)],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: _gameOver
                  ? _buildEndScreen(
                      icon: Icons.sentiment_dissatisfied,
                      title: 'Juego terminado',
                      subtitle: '¡Sigue practicando para mantenerte seguro!',
                      color: AppTheme.dangerRed,
                      isDark: isDark,
                      textColor: textColor,
                    )
                  : _gameWon
                      ? _buildEndScreen(
                          icon: Icons.emoji_events,
                          title: '¡Felicidades!',
                          subtitle: 'Respondiste todas las preguntas correctamente.',
                          color: AppTheme.warningYellow,
                          isDark: isDark,
                          textColor: textColor,
                        )
                      : _buildGameContent(isDark, textColor),
            ),
            // Confetti overlay
            if (_confetti.isNotEmpty)
              AnimatedBuilder(
                animation: _confettiController,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size.infinite,
                    painter: _ConfettiPainter(_confetti, _confettiController.value),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameContent(bool isDark, Color textColor) {
    final question = _questions[_currentQuestion];

    return Column(
      children: [
        // Top bar
        _buildTopBar(isDark, textColor),
        // Timer circular
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildCircularTimer(isDark),
        ),
        // Progress
        _buildProgressBar(isDark),
        // Category badge
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: _buildCategoryBadge(question.category, isDark),
        ),
        // Question + options
        Expanded(
          child: AnimatedBuilder(
            animation: _questionSlideController,
            builder: (context, _) {
              final slide = 1.0 - _questionSlideController.value;
              return Transform.translate(
                offset: Offset(slide * 30, 0),
                child: Opacity(
                  opacity: slide < 0.01 ? 1.0 : 0.0,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Question card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [const Color(0xFF1E1E3E), const Color(0xFF2A2A5E)]
                                  : [Colors.white, const Color(0xFFF8F9FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFF1565C0).withValues(alpha: 0.15),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.quiz, size: 18, color: Color(0xFF1565C0)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  question.question,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Options
                        ...List.generate(question.options.length, (index) {
                          return _buildOption(index, question, isDark, textColor);
                        }),
                        const SizedBox(height: 12),
                        // Feedback
                        if (_isAnswered) _buildFeedback(isDark),
                        if (_isAnswered && !_gameOver && !_gameWon)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _nextQuestion,
                                icon: Icon(
                                  _isLastQuestion ? Icons.flag : Icons.arrow_forward,
                                  size: 20,
                                ),
                                label: Text(
                                  _isLastQuestion ? 'Ver resultados' : 'Siguiente pregunta',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryGreen,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 4,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBadge(String category, bool isDark) {
    IconData icon;
    switch (category) {
      case 'Emergencias': icon = Icons.emergency; break;
      case 'Geografía': icon = Icons.map; break;
      case 'Seguridad': icon = Icons.shield; break;
      case 'Salud': icon = Icons.local_hospital; break;
      case 'Historia': icon = Icons.history_edu; break;
      default: icon = Icons.quiz;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF1565C0).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1565C0)),
          const SizedBox(width: 6),
          Text(
            category,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1565C0),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TIMER CIRCULAR MEJORADO
  // ============================================================
  Widget _buildCircularTimer(bool isDark) {
    final progress = _timeLeft / 15;
    final timerColor = progress > 0.5
        ? AppTheme.safeGreen
        : progress > 0.25
            ? AppTheme.warningYellow
            : AppTheme.dangerRed;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(
              value: progress,
              backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(timerColor),
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '$_timeLeft',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: timerColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Lives
          Row(
            children: List.generate(3, (i) {
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  i < _lives ? Icons.favorite : Icons.favorite_border,
                  color: i < _lives
                      ? AppTheme.dangerRed
                      : (isDark ? Colors.grey[700] : Colors.grey[300]),
                  size: 22,
                ),
              );
            }),
          ),
          const Spacer(),
          // Streak
          if (_streak >= 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.alertOrange.withValues(alpha: 0.2),
                    AppTheme.alertOrange.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.alertOrange.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department, size: 16, color: AppTheme.alertOrange),
                  const SizedBox(width: 4),
                  Text(
                    'Racha x$_streak',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.alertOrange),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          // Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.warningYellow.withValues(alpha: 0.15),
                  AppTheme.warningYellow.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warningYellow.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stars, size: 16, color: AppTheme.warningYellow),
                const SizedBox(width: 4),
                Text(
                  '$_score',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.warningYellow),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_questions.length, (i) {
          final isDone = i < _currentQuestion;
          final isCurrent = i == _currentQuestion;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: i == _currentQuestion ? 24 : 8,
            height: 6,
            decoration: BoxDecoration(
              gradient: isDone
                  ? const LinearGradient(colors: [AppTheme.primaryGreen, AppTheme.safeGreen])
                  : isCurrent
                      ? const LinearGradient(colors: [AppTheme.primaryLight, AppTheme.primaryGreen])
                      : null,
              color: isDone || isCurrent ? null : (isDark ? Colors.grey[700] : Colors.grey[300]),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }

  // ============================================================
  // OPCIONES MEJORADAS CON ICONOS
  // ============================================================
  Widget _buildOption(int index, TriviaQuestion question, bool isDark, Color textColor) {
    final option = question.options[index];
    final isCorrectAnswer = index == question.correctIndex;
    final isSelected = _selectedIndex == index;

    Color? bgColor;
    Color? borderColor;
    Color? fgColor;
    IconData? icon;

    if (_isAnswered) {
      if (isCorrectAnswer) {
        bgColor = AppTheme.safeGreen.withValues(alpha: 0.12);
        borderColor = AppTheme.safeGreen;
        fgColor = AppTheme.safeGreen;
        icon = Icons.check_circle_rounded;
      } else if (isSelected) {
        bgColor = AppTheme.dangerRed.withValues(alpha: 0.12);
        borderColor = AppTheme.dangerRed;
        fgColor = AppTheme.dangerRed;
        icon = Icons.cancel_rounded;
      }
    }

    return GestureDetector(
      onTap: _isAnswered ? null : () => _selectAnswer(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor ?? (isDark ? const Color(0xFF1E1E3E) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor ?? (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            width: (isSelected || isCorrectAnswer) && _isAnswered ? 2 : 1,
          ),
          boxShadow: [
            if (!_isAnswered)
              BoxShadow(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: fgColor?.withValues(alpha: 0.12) ?? (isDark ? const Color(0xFF2A2A5E) : Colors.grey[100]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 18, color: fgColor)
                    : Text(
                        String.fromCharCode(65 + index),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                  fontWeight: isSelected || isCorrectAnswer ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            // Option index
            if (!_isAnswered)
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[500] : Colors.grey[400]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FEEDBACK MEJORADO
  // ============================================================
  Widget _buildFeedback(bool isDark) {
    return AnimatedBuilder(
      animation: _feedbackAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: _feedbackAnim.value,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isCorrect
                    ? [AppTheme.safeGreen.withValues(alpha: 0.08), AppTheme.safeGreen.withValues(alpha: 0.02)]
                    : [AppTheme.dangerRed.withValues(alpha: 0.08), AppTheme.dangerRed.withValues(alpha: 0.02)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isCorrect
                    ? AppTheme.safeGreen.withValues(alpha: 0.2)
                    : AppTheme.dangerRed.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: (_isCorrect ? AppTheme.safeGreen : AppTheme.dangerRed).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isCorrect ? Icons.check_circle : Icons.cancel,
                        color: _isCorrect ? AppTheme.safeGreen : AppTheme.dangerRed,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _feedbackMessage ?? '',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _isCorrect ? AppTheme.safeGreen : AppTheme.dangerRed,
                      ),
                    ),
                    if (_streak >= 2 && _isCorrect) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.local_fire_department, size: 18, color: AppTheme.alertOrange),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Bonus points
                if (_isCorrect && _timeLeft > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.warningYellow.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer, size: 12, color: AppTheme.warningYellow),
                        const SizedBox(width: 4),
                        Text(
                          '+$_timeLeft bonus por rapidez',
                          style: const TextStyle(fontSize: 11, color: AppTheme.warningYellow, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                Text(
                  _questions[_currentQuestion].explanation,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // END SCREEN MEJORADO
  // ============================================================
  Widget _buildEndScreen({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required Color textColor,
  }) {
    // Rank
    String rank;
    Color rankColor;
    if (_score >= 150) {
      rank = '🏆 ¡Experto en seguridad!';
      rankColor = AppTheme.warningYellow;
    } else if (_score >= 100) {
      rank = '🥈 Guardián de Collique';
      rankColor = AppTheme.shieldBlue;
    } else if (_score >= 50) {
      rank = '🥉 Vigilante aprendíz';
      rankColor = AppTheme.safeGreen;
    } else {
      rank = '📖 ¡Sigue aprendiendo!';
      rankColor = Colors.grey;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.05)],
                ),
                border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
              ),
              child: Icon(icon, size: 48, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [rankColor.withValues(alpha: 0.15), rankColor.withValues(alpha: 0.05)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: rankColor.withValues(alpha: 0.2)),
              ),
              child: Text(
                rank,
                style: TextStyle(fontSize: 15, color: rankColor, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[500])),
            const SizedBox(height: 28),
            // Score card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E3E) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: color.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.1),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text('Puntaje final', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(height: 4),
                  Text(
                    '$_score',
                    style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: color),
                  ),
                  Text('puntos', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatChip(Icons.favorite, '$_lives/3 vidas', AppTheme.dangerRed),
                      const SizedBox(width: 12),
                      _buildStatChip(Icons.quiz_outlined, '${_currentQuestion + 1} preguntas', AppTheme.shieldBlue),
                      if (_streak >= 2) ...[
                        const SizedBox(width: 12),
                        _buildStatChip(Icons.local_fire_department, 'Racha x$_streak', AppTheme.alertOrange),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _restartGame,
                icon: const Icon(Icons.replay, size: 22),
                label: const Text(
                  'JUGAR DE NUEVO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 8,
                  shadowColor: AppTheme.primaryGreen.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

// ============================================================
// MODELOS
// ============================================================
class TriviaQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String category;

  TriviaQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.category = 'General',
  });
}

class _ConfettiParticle {
  double x, y, vx, vy;
  final Color color;
  final double size;
  double rotation;
  _ConfettiParticle({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.color, required this.size,
    required this.rotation,
  });
}

// ============================================================
// CONFETTI PAINTER
// ============================================================
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final x = p.x * size.width + p.vx * progress * 500;
      final y = (p.y + p.vy * progress * 500) * size.height;
      if (y < 0 || y > size.height) continue;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + progress * 10);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
        Paint()..color = p.color.withValues(alpha: (1 - progress).clamp(0, 1)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
