import 'dart:math';
import 'package:flutter/material.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/screens/entry/code_assignment_screen.dart';

class CaptchaScreen extends StatefulWidget {
  final int zone;

  const CaptchaScreen({super.key, required this.zone});

  @override
  State<CaptchaScreen> createState() => _CaptchaScreenState();
}

class _CaptchaScreenState extends State<CaptchaScreen>
    with SingleTickerProviderStateMixin {
  String? _challengeText;
  int? _correctIndex;
  bool _answered = false;
  bool _success = false;
  late AnimationController _animController;

  final List<Map<String, String>> _challenges = [
    {
      'text': 'Presiona el 🛵 Mototaxi',
      'options': '🚗 Auto|🛵 Mototaxi|🚌 Bus|🚲 Bicicleta',
      'answer': '🛵 Mototaxi',
    },
    {
      'text': 'Presiona el 🔔 Timbre de alarma',
      'options': '📞 Teléfono|🔔 Timbre|🎵 Música|📺 TV',
      'answer': '🔔 Timbre',
    },
    {
      'text': 'Presiona la 🚔 Camioneta de Serenazgo',
      'options': '🚑 Ambulancia|🚒 Bomberos|🚔 Serenazgo|🚌 Municipal',
      'answer': '🚔 Serenazgo',
    },
    {
      'text': 'Presiona la 💡 Luz prendida',
      'options': '💡 Luz|🔦 Linterna|🕯️ Vela|⚡ Rayo',
      'answer': '💡 Luz',
    },
    {
      'text': 'Presiona la 🏠 Casa segura',
      'options': '🏢 Edificio|🏠 Casa|🏪 Tienda|🏥 Hospital',
      'answer': '🏠 Casa',
    },
    {
      'text': 'Presiona el 🚧 Pasaje en obra',
      'options': '🚧 Pasaje|🛣️ Avenida|🛤️ Tren|🛑 Pare',
      'answer': '🚧 Pasaje',
    },
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _generateChallenge();
  }

  void _generateChallenge() {
    final random = Random();
    final challenge = _challenges[random.nextInt(_challenges.length)];
    final options = challenge['options']!.split('|');
    final answer = challenge['answer']!;

    // Shuffle options
    final shuffled = List<String>.from(options)..shuffle();
    final correctIdx = shuffled.indexOf(answer);

    setState(() {
      _challengeText = challenge['text'];
      _correctIndex = correctIdx;
      _options = shuffled;
      _answered = false;
      _success = false;
    });
    _animController.reset();
    _animController.forward();
  }

  late List<String> _options;

  void _checkAnswer(int index) {
    if (_answered) return;
    setState(() {
      _answered = true;
      _success = index == _correctIndex;
    });

    if (_success) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => CodeAssignmentScreen(zone: widget.zone),
            ),
          );
        }
      });
    } else {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _generateChallenge();
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryGreen, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    '🛡️ Verificación',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Zona ${widget.zone}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Demuestra que eres un vecino real',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // Challenge card
            if (_challengeText != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      FadeTransition(
                        opacity: _animController,
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.psychology_outlined,
                                    size: 40,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  _challengeText!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_answered && !_success)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.close, color: AppTheme.dangerRed),
                              SizedBox(width: 8),
                              Text(
                                'Respuesta incorrecta. Intenta de nuevo...',
                                style: TextStyle(color: AppTheme.dangerRed, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      if (_answered && _success)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.safeGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.safeGreen.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, color: AppTheme.safeGreen),
                              SizedBox(width: 8),
                              Text(
                                '✅ ¡Verificado! Ingresando...',
                                style: TextStyle(color: AppTheme.safeGreen, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Options grid
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.5,
                          shrinkWrap: true,
                          children: List.generate(_options.length, (index) {
                            final isCorrect =
                                _answered && index == _correctIndex;

                            return GestureDetector(
                              onTap: () => _checkAnswer(index),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                decoration: BoxDecoration(
                                  color: _answered
                                      ? (isCorrect
                                          ? AppTheme.safeGreen
                                          : Colors.grey[200])
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _answered
                                        ? (isCorrect
                                            ? AppTheme.safeGreen
                                            : Colors.grey[300]!)
                                        : Colors.grey[300]!,
                                    width: isCorrect ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    _options[index],
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: isCorrect
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: _answered
                                          ? (isCorrect
                                              ? Colors.white
                                              : Colors.grey[500])
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
