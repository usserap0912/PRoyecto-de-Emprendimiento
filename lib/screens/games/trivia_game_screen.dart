import 'dart:async';
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
    with SingleTickerProviderStateMixin {
  int _currentQuestion = 0;
  int _score = 0;
  int _lives = 3;
  int _streak = 0;
  int _timeLeft = 15;
  Timer? _timer;
  bool _isAnswered = false;
  int? _selectedIndex;
  bool _isCorrect = false;
  late AnimationController _animController;
  late Animation<double> _feedbackAnim;
  String? _feedbackMessage;

  // Game state
  bool _gameOver = false;
  bool _gameWon = false;

  final SupabaseService _supabase = SupabaseService();

  // Questions about Collique safety
  final List<TriviaQuestion> _questions = [
    TriviaQuestion(
      question: '¿Cuál es el número de emergencia de la Policía Nacional del Perú?',
      options: ['105', '106', '107', '116'],
      correctIndex: 0,
      explanation: 'El 105 es el número de la Policía Nacional. El 106 es para emergencias médicas (SAMU).',
    ),
    TriviaQuestion(
      question: '¿Qué zona de Collique limita con las Lomas de Collique?',
      options: ['1ra Zona', '3ra Zona', '5ta Zona', 'Av. Revolución'],
      correctIndex: 2,
      explanation: 'La 5ta Zona de Collique se encuentra en las partes altas, colindando con las Lomas de Collique.',
    ),
    TriviaQuestion(
      question: '¿Cuál es el número del SAMU (emergencias médicas)?',
      options: ['105', '106', '107', '116'],
      correctIndex: 1,
      explanation: 'El SAMU se marca marcando el 106 para emergencias médicas.',
    ),
    TriviaQuestion(
      question: '¿Qué avenida principal atraviesa Collique?',
      options: ['Av. Túpac Amaru', 'Av. Revolución', 'Av. Collique', 'Av. Universitaria'],
      correctIndex: 1,
      explanation: 'La Av. Revolución es la vía principal que atraviesa las zonas de Collique.',
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
    ),
    TriviaQuestion(
      question: '¿En qué distrito se encuentra Collique?',
      options: ['Los Olivos', 'Comas', 'Independencia', 'Carabayllo'],
      correctIndex: 1,
      explanation: 'Collique es un sector del distrito de Comas, en Lima Norte.',
    ),
    TriviaQuestion(
      question: '¿Qué hospital da servicio a la zona de Collique?',
      options: ['Hospital Cayetano Heredia', 'Hospital Sergio Bernales', 'Hospital Loayza', 'Hospital Almenara'],
      correctIndex: 1,
      explanation: 'El Hospital Sergio Bernales, ubicado en Collique, es el principal centro de salud de la zona.',
    ),
    TriviaQuestion(
      question: '¿Cuál es el número de emergencia nacional para bomberos?',
      options: ['105', '106', '107', '116'],
      correctIndex: 3,
      explanation: 'El 116 es el número de los Bomberos del Perú a nivel nacional.',
    ),
    TriviaQuestion(
      question: '¿Qué cultura prehispánica habitó la zona de Collique?',
      options: ['Los Incas', 'Los Colli', 'Los Moche', 'Los Nazca'],
      correctIndex: 1,
      explanation: 'La Cultura Colli habitó esta zona. Su fortaleza y museo son parte importante de Collique.',
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
    ),
    TriviaQuestion(
      question: '¿Qué significa la etiqueta ROJA en un reporte de SafeZone?',
      options: ['Peligro inminente', 'Precaución', 'Resuelto', 'Información general'],
      correctIndex: 0,
      explanation: 'La etiqueta ROJA indica un peligro inminente que requiere atención inmediata.',
    ),
    TriviaQuestion(
      question: '¿Qué zona de Collique es conocida por su mercado principal?',
      options: ['1ra Zona', '2da Zona', '3ra Zona', '4ta Zona'],
      correctIndex: 1,
      explanation: 'La 2da Zona de Collique alberga el mercado principal y la zona comercial más activa.',
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
    ),
    TriviaQuestion(
      question: '¿Cómo se llama el sitio arqueológico ubicado en Collique?',
      options: ['Huaca Pucllana', 'Fortaleza de Collique', 'Pachacámac', 'Caral'],
      correctIndex: 1,
      explanation: 'La Fortaleza de Collique, hoy Museo de los Colli, es el principal sitio arqueológico de la zona.',
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
    ),
  ];

  bool get _isLastQuestion => _currentQuestion >= _questions.length - 1;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _feedbackAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _shuffleQuestions();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _shuffleQuestions() {
    _questions.shuffle();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_gameOver || _gameWon) return;
    setState(() => _timeLeft = 15);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_timeLeft <= 1) {
        timer.cancel();
        if (!_isAnswered) {
          _handleTimeout();
        }
      } else {
        setState(() => _timeLeft--);
      }
    });
  }

  void _handleTimeout() {
    if (!mounted) return;
    setState(() {
      _isAnswered = true;
      _selectedIndex = -1; // timeout
      _isCorrect = false;
      _lives--;
      _streak = 0;
      _feedbackMessage = '⏰ ¡Se acabó el tiempo!';
    });
    _animController.forward(from: 0);
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
    } else {
      setState(() {
        _lives--;
        _streak = 0;
      });
    }

    _animController.forward(from: 0);
    _checkGameOver();
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
    _animController.reset();
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
    _animController.reset();
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _gameOver || _gameWon ? 'Resultados' : 'Trivia de Seguridad',
        ),
        centerTitle: true,
        actions: [
          if (!_gameOver && !_gameWon)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  'Pregunta ${_currentQuestion + 1}/${_questions.length}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
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
    );
  }

  Widget _buildGameContent(bool isDark, Color textColor) {
    final question = _questions[_currentQuestion];

    return Column(
      children: [
        // Top bar: Lives, Score, Streak
        _buildTopBar(isDark, textColor),
        // Timer bar
        _buildTimerBar(isDark),
        // Progress indicator
        _buildProgressBar(isDark),
        // Question card
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Question
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    question.question,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      height: 1.4,
                    ),
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
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _nextQuestion,
                        icon: Icon(
                          _isLastQuestion ? Icons.flag : Icons.arrow_forward,
                          size: 20,
                        ),
                        label: Text(
                          _isLastQuestion
                              ? 'Ver resultados'
                              : 'Siguiente pregunta',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
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
                    AppTheme.alertOrange.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.alertOrange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department,
                      size: 16, color: AppTheme.alertOrange),
                  const SizedBox(width: 4),
                  Text(
                    'Racha x$_streak',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.alertOrange,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          // Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stars, size: 16, color: AppTheme.warningYellow),
                const SizedBox(width: 4),
                Text(
                  '$_score',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerBar(bool isDark) {
    final progress = _timeLeft / 15;
    final timerColor = progress > 0.5
        ? AppTheme.safeGreen
        : progress > 0.25
            ? AppTheme.warningYellow
            : AppTheme.dangerRed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          valueColor: AlwaysStoppedAnimation(timerColor),
          minHeight: 6,
        ),
      ),
    );
  }

  Widget _buildProgressBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_questions.length, (i) {
          final isDone = i < _currentQuestion;
          final isCurrent = i == _currentQuestion;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: i == _currentQuestion ? 20 : 8,
            height: 6,
            decoration: BoxDecoration(
              color: isDone
                  ? AppTheme.primaryGreen
                  : isCurrent
                      ? AppTheme.primaryLight
                      : (isDark ? Colors.grey[700] : Colors.grey[300]),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }

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
        bgColor = AppTheme.safeGreen.withValues(alpha: 0.15);
        borderColor = AppTheme.safeGreen;
        fgColor = AppTheme.safeGreen;
        icon = Icons.check_circle;
      } else if (isSelected) {
        bgColor = AppTheme.dangerRed.withValues(alpha: 0.15);
        borderColor = AppTheme.dangerRed;
        fgColor = AppTheme.dangerRed;
        icon = Icons.cancel;
      }
    }

    return GestureDetector(
      onTap: _isAnswered ? null : () => _selectAnswer(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor ?? (isDark ? AppTheme.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor ??
                (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            width: (isSelected || isCorrectAnswer) && _isAnswered ? 2 : 1,
          ),
          boxShadow: [
            if (!_isAnswered)
              BoxShadow(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: fgColor?.withValues(alpha: 0.12) ??
                    (isDark ? Colors.grey[800] : Colors.grey[100]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 16, color: fgColor)
                    : Text(
                        String.fromCharCode(65 + index),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                  fontWeight: isSelected || isCorrectAnswer
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedback(bool isDark) {
    return AnimatedBuilder(
      animation: _feedbackAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: _feedbackAnim.value,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isCorrect
                  ? AppTheme.safeGreen.withValues(alpha: 0.1)
                  : AppTheme.dangerRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isCorrect
                    ? AppTheme.safeGreen.withValues(alpha: 0.3)
                    : AppTheme.dangerRed.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isCorrect ? Icons.check_circle : Icons.cancel,
                      color: _isCorrect ? AppTheme.safeGreen : AppTheme.dangerRed,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
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
                      Icon(Icons.local_fire_department,
                          size: 18, color: AppTheme.alertOrange),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
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

  Widget _buildEndScreen({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required Color textColor,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: color),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[500]),
            ),
            const SizedBox(height: 32),
            // Score card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Puntaje final',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_score',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'puntos',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatChip(
                        Icons.favorite,
                        '$_lives/3 vidas',
                        AppTheme.dangerRed,
                      ),
                      const SizedBox(width: 12),
                      _buildStatChip(
                        Icons.quiz_outlined,
                        '${_currentQuestion + 1} preguntas',
                        AppTheme.shieldBlue,
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
                onPressed: _restartGame,
                icon: const Icon(Icons.replay, size: 22),
                label: const Text(
                  'JUGAR DE NUEVO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
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

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}

class TriviaQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  TriviaQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}
