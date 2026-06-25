import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/services/supabase_service.dart';

class SosScreen extends StatefulWidget {
  final String userCode;
  final int zone;

  const SosScreen({
    super.key,
    required this.userCode,
    required this.zone,
  });

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  bool _isActivated = false;
  bool _isCountingDown = false;
  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _vibrationTimer;
  bool _alertSent = false;
  bool _saveError = false;
  late AnimationController _pulseAnim;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseAnim, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _vibrationTimer?.cancel();
    _pulseAnim.dispose();
    super.dispose();
  }

  void _startSos() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isCountingDown = true;
      _countdown = 3;
      _alertSent = false;
      _saveError = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _countdown--;
        });
      }

      if (_countdown == 0) {
        timer.cancel();
        _sendSosAlert();
      }
    });
  }

  void _cancelSos() {
    _countdownTimer?.cancel();
    HapticFeedback.mediumImpact();
    if (mounted) {
      setState(() {
        _isCountingDown = false;
        _isActivated = false;
        _countdown = 3;
      });
    }
  }

  Future<void> _sendSosAlert() async {
    if (!mounted) return;
    setState(() {
      _isCountingDown = false;
      _isActivated = true;
    });

    // Obtener ubicación
    final locationService = LocationService();
    final position = await locationService.getCurrentLocation();

    String? address;
    double? lat;
    double? lng;

    if (position != null) {
      lat = position.latitude;
      lng = position.longitude;
      address = await locationService.getAddressFromCoordinates(lat, lng);
    }

    // Guardar en Supabase
    final supabase = SupabaseService();
    final saved = await supabase.insertSosAlert({
      'user_code': widget.userCode,
      'latitude': lat ?? LocationService.colliqueLat,
      'longitude': lng ?? LocationService.colliqueLng,
      'address': address,
      'status': 'activo',
    });

    if (mounted) {
      setState(() {
        _alertSent = true;
        _saveError = !saved;
      });
    }

    // Vibración de alerta
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      HapticFeedback.heavyImpact();
    });

    // Auto-detener vibración después de 3 segundos
    Future.delayed(const Duration(seconds: 3), () {
      _vibrationTimer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('S.O.S.'),
        backgroundColor: AppTheme.sosRed,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.sosRed, AppTheme.sosDarkRed],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              if (!_isCountingDown && !_isActivated)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline, color: Colors.white70, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Solo para emergencias reales',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      '¿Estás en peligro?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Presiona el botón para enviar\nuna alerta con tu ubicación',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),

              const Spacer(),

              if (_isCountingDown)
                Column(
                  children: [
                    const Text(
                      'ALERTA EN...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        '$_countdown',
                        key: ValueKey(_countdown),
                        style: const TextStyle(
                          fontSize: 100,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _cancelSos,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'CANCELAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

              if (_isActivated && _alertSent)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '🚨 ¡ALERTA ENVIADA!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tu ubicación ha sido compartida\ncon la red vecinal de Collique',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                    if (_saveError)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Modo offline - la alerta se guardará cuando tengas conexión',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.amber, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        if (mounted) {
                          setState(() {
                            _isActivated = false;
                            _alertSent = false;
                            _saveError = false;
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.sosRed,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                      ),
                      child: const Text(
                        'DESACTIVAR ALERTA',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

              if (!_isCountingDown && !_isActivated)
                GestureDetector(
                  onLongPress: _startSos,
                  onTap: _startSos,
                  child: AnimatedBuilder(
                    animation: _pulseScale,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseScale.value,
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [
                                Color(0xFFE53935),
                                Color(0xFFB71C1C),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.5),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 4,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.sos,
                                size: 48,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'S.O.S.',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 4,
                                ),
                              ),
                              Text(
                                'Presiona 3s',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              const Spacer(),

              if (!_isCountingDown && !_isActivated)
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.location_on, color: Colors.white.withValues(alpha: 0.6), size: 20),
                      const SizedBox(height: 4),
                      Text(
                        'Se compartirá tu ubicación GPS exacta',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

              if (_isActivated && !_alertSent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
