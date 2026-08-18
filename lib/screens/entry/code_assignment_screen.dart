import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/screens/home/home_screen.dart';

class CodeAssignmentScreen extends StatefulWidget {
  final int zone;

  const CodeAssignmentScreen({super.key, required this.zone});

  @override
  State<CodeAssignmentScreen> createState() => _CodeAssignmentScreenState();
}

class _CodeAssignmentScreenState extends State<CodeAssignmentScreen>
    with SingleTickerProviderStateMixin {
  // Inicializamos con un valor por defecto para evitar el parpadeo
  String _userCode = '';
  String _displayCode = '--------';
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  final SupabaseService _supabase = SupabaseService();
  bool _isSaving = false;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));
    _scaleAnim = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    // El backend actual usa el alias pseudónimo legado guardado localmente.
    _initializeUserCode();
  }

  Future<void> _initializeUserCode() async {
    if (kDebugMode) debugPrint('[ENTRY] code_assignment_started');
    setState(() => _isSaving = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      final existingCode = preferences.getString('user_device_code');
      _userCode = existingCode ?? _generateCode();
      await preferences.setString('user_device_code', _userCode);
      await preferences.setInt('user_zone', widget.zone);

      final profileSaved = await _supabase.ensureLegacyProfile(
        userCode: _userCode,
        zone: widget.zone,
      );
      if (kDebugMode) {
        debugPrint(
          profileSaved
              ? '[ENTRY] legacy_profile_ready'
              : '[ENTRY] legacy_profile_not_confirmed',
        );
      }
      if (!mounted) return;
      setState(() {
        _displayCode = _userCode;
        _isReady = true;
      });
      _animController.forward();
      if (kDebugMode) debugPrint('[ENTRY] neighbor_code_ready');
    } catch (error) {
      if (kDebugMode) debugPrint('[ENTRY] code_assignment_failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos preparar tu código. Inténtalo nuevamente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _generateCode() {
    final random = Random();
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const numbers = '0123456789';
    final suffix =
        '${letters[random.nextInt(letters.length)]}'
        '${numbers[random.nextInt(numbers.length)]}'
        '${letters[random.nextInt(letters.length)]}'
        '${numbers[random.nextInt(numbers.length)]}';
    return 'User-$suffix';
  }

  void _enterApp() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(userCode: _userCode, zone: widget.zone),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fondo definido desde el inicio para evitar parpadeo
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryGreen, AppTheme.primaryDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Logo oficial de la app en la parte superior central
              FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 100,
                    height: 100,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Image.asset(
                      'assets/icons/logo-app.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.shield,
                          size: 48,
                          color: Colors.white,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  children: [
                    const Text(
                      '¡Bienvenido a SafeZone!',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Zona ${widget.zone} • Collique',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Tarjeta del código
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Tu código de vecino',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Mostrar placeholder o código real
                          AnimatedBuilder(
                            animation: _animController,
                            builder: (context, child) {
                              return Text(
                                _displayCode,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 3,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.visibility_off,
                                  size: 16,
                                  color: Colors.white70,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Tu identidad es anónima',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_isSaving)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Guardando tu identidad...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Este código te identifica de forma anónima dentro de SafeZone.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Botón de ingreso
              Padding(
                padding: const EdgeInsets.all(32),
                child: SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : _isReady
                        ? _enterApp
                        : _initializeUserCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryGreen,
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: 0.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      'CONTINUAR',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
