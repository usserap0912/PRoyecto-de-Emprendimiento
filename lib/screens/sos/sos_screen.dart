import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:safezone/config/map_config.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/services/notification_service.dart';
import 'package:safezone/services/sos_state_service.dart';
import 'package:uuid/uuid.dart';

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
  bool _alertSent = false;
  bool _saveError = false;

  // Animaciones
  late AnimationController _pulseAnim;
  late Animation<double> _pulseScale;
  late AnimationController _mapBlinkController;
  late Animation<double> _mapBlinkOpacity;

  // Ubicación
  double? _userLat;
  double? _userLng;
  String? _userAddress;
  bool _isLocating = false;

  // Comisaría más cercana
  Map<String, dynamic>? _nearestStation;
  String _distanceText = '';

  // Control de mapa
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();

    // Pulso del botón SOS
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseAnim, curve: Curves.easeInOut),
    );

    // Parpadeo del marcador en el mapa
    _mapBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _mapBlinkOpacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _mapBlinkController, curve: Curves.easeInOut),
    );

    // Obtener ubicación y comisaría más cercana al iniciar
    _loadLocationAndNearestStation();
  }

  Future<void> _loadLocationAndNearestStation() async {
    setState(() => _isLocating = true);
    try {
      final locationService = LocationService();
      final position = await locationService.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _userLat = position.latitude;
          _userLng = position.longitude;
        });
        // Obtener dirección
        final address =
            await locationService.getAddressFromCoordinates(_userLat!, _userLng!);
        if (mounted) {
          setState(() => _userAddress = address);
        }
        // Encontrar comisaría más cercana
        _updateNearestStation(_userLat!, _userLng!);
      }
    } catch (e) {
      debugPrint('SosScreen: Error cargando ubicación: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _updateNearestStation(double lat, double lng) {
    final station = LocationService.findNearestStation(lat, lng);
    final distance = station['distance_meters'] as double;
    setState(() {
      _nearestStation = station;
      _distanceText = LocationService.formatDistance(distance);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseAnim.dispose();
    _mapBlinkController.dispose();
    _mapController.dispose();
    // Asegurar que la alarma se detenga
    SoundService().stop(stopLooping: true);
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
    SoundService().stop(stopLooping: true);
    // Notificar que el S.O.S. ya no está activo
    SosStateService().setActive(false);
    if (mounted) {
      setState(() {
        _isCountingDown = false;
        _isActivated = false;
        _alertSent = false;
        _countdown = 3;
      });
    }
  }

  Future<void> _sendSosAlert() async {
    if (!mounted) return;

    // Iniciar alarma SOS en loop
    SoundService().playLoopingSosAlarm();
    HapticFeedback.heavyImpact();

    setState(() {
      _isCountingDown = false;
      _isActivated = true;
    });

    // Notificar a otras pantallas (ej: el Mapa) que el S.O.S. está activo
    SosStateService().setActive(true);

    // Obtener ubicación (actualizar si no tenemos)
    final locationService = LocationService();
    if (_userLat == null) {
      final position = await locationService.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _userLat = position.latitude;
          _userLng = position.longitude;
        });
        final address =
            await locationService.getAddressFromCoordinates(_userLat!, _userLng!);
        if (mounted) setState(() => _userAddress = address);
        _updateNearestStation(_userLat!, _userLng!);
      }
    }

    final lat = _userLat ?? LocationService.colliqueLat;
    final lng = _userLng ?? LocationService.colliqueLng;

    // Guardar en Supabase
    final supabase = SupabaseService();
    final saved = await supabase.insertSosAlert({
      'user_code': widget.userCode,
      'latitude': lat,
      'longitude': lng,
      'address': _userAddress,
      'status': 'activo',
    });

    // ============================================================
    // 1️⃣ PUBLICAR EN EL MURO (tabla reports)
    // ============================================================
    try {
      await supabase.client.from('reports').insert({
        'user_code': widget.userCode,
        'zone': widget.zone,
        'category': 'sos',
        'risk_level': 'critica',
        'description': _userAddress != null
            ? '🚨 ALERTA S.O.S. - Un vecino necesita ayuda urgente en $_userAddress'
            : '🚨 ALERTA S.O.S. - Un vecino necesita ayuda urgente en Collique',
        'latitude': lat,
        'longitude': lng,
        'address': _userAddress,
        'tag': 'rojo',
        'status': 'activo',
        'created_at': DateTime.now().toIso8601String(),
      });
      
      // Feedback intenso: vibración al publicar en el Muro
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint('SosScreen: Error publicando en Muro: $e');
    }

    // ============================================================
    // 2️⃣ BROADCAST EN CHAT COMUNITARIO
    // ============================================================
    try {
      await supabase.client.from('chat_messages').insert({
        'id': const Uuid().v4(),
        'user_code': '🚨 SISTEMA',
        'content': _userAddress != null
            ? '🚨 ¡ALERTA S.O.S. ACTIVA! Un vecino de Zona ${widget.zone} necesita ayuda urgente en $_userAddress. ¡Si estás cerca, por favor ayuda! 🙏'
            : '🚨 ¡ALERTA S.O.S. ACTIVA! Un vecino de Zona ${widget.zone} necesita ayuda urgente. ¡Si estás cerca, por favor ayuda! 🙏',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('SosScreen: Error en broadcast chat: $e');
    }

    // ============================================================
    // 3️⃣ OTORGAR PUNTOS VECINALES (+20 por activar SOS)
    // ============================================================
    supabase.addVecinoPoints(
      userCode: widget.userCode,
      points: 20,
      reason: 'sos',
      description: 'Activó una alerta SOS en Zona ${widget.zone}',
    );

    // ============================================================
    // 4️⃣ SONIDO DE CONFIRMACIÓN (siempre, aunque falle el muro)
    // ============================================================
    SoundService().play('sos_sent');

    // ============================================================
    // 5️⃣ NOTIFICACIÓN LOCAL
    // ============================================================
    NotificationService().showSosAlert(
      userCode: widget.userCode,
      address: _userAddress ?? 'Zona ${widget.zone}',
    );

    // Animar el mapa a la ubicación
    try {
      _mapController.move(LatLng(lat, lng), 16.0);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _alertSent = true;
        _saveError = !saved;
      });
    }
  }

  void _deactivateAlert() {
    SoundService().stop(stopLooping: true);
    HapticFeedback.mediumImpact();
    // Notificar que el S.O.S. ya no está activo
    SosStateService().setActive(false);
    if (mounted) {
      setState(() {
        _isActivated = false;
        _alertSent = false;
        _saveError = false;
      });
    }
  }

  Future<void> _callEmergeny(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se puede llamar al $phone'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Abre WhatsApp con un mensaje de SOS precargado incluyendo ubicación.
  Future<void> _sendWhatsAppLocation() async {
    final lat = _userLat ?? LocationService.colliqueLat;
    final lng = _userLng ?? LocationService.colliqueLng;
    final mapsUrl = 'https://maps.google.com/maps?q=$lat,$lng';

    final message = Uri.encodeComponent(
      '🚨 ¡ESTO ES UNA EMERGENCIA!\n'
      'Necesito ayuda urgente. Mi ubicación actual es:\n'
      '📍 ${_userAddress ?? "Collique, Comas"}\n'
      '🔗 $mapsUrl\n'
      '👤 Zona ${widget.zone}\n\n'
      '¡Por favor, ayuda! 🙏',
    );

    // Intentar abrir WhatsApp primero con el esquema nativo
    final whatsappUri = Uri.parse('whatsapp://send?text=$message');
    final webWhatsappUri = Uri.parse('https://wa.me/?text=$message');

    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri);
    } else if (await canLaunchUrl(webWhatsappUri)) {
      await launchUrl(webWhatsappUri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp no está instalado en este dispositivo'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('S.O.S.'),
        backgroundColor: AppTheme.sosRed,
        leading: _isActivated
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.warning_amber_rounded, color: Colors.white),
              )
            : null,
        actions: _isActivated
            ? [
                // Indicador de alarma activa
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'ALARMA ACTIVA',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            : null,
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
          child: _isActivated && _alertSent
              ? _buildActivatedView(isDark)
              : _buildIdleOrCountdownView(),
        ),
      ),
    );
  }

  // ============================================================
  // VISTA IDLE + COUNTDOWN
  // ============================================================
  Widget _buildIdleOrCountdownView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 12),

        // === INFO BANNER (solo idle) ===
        if (!_isCountingDown && !_isActivated)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Solo para emergencias reales',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

        // === TÍTULO ===
        if (!_isCountingDown && !_isActivated) ...[
          const SizedBox(height: 28),
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

        const Spacer(),

        // === COUNTDOWN ===
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
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.4)),
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

        // === BOTÓN SOS ===
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
                        const Icon(Icons.sos, size: 48, color: Colors.white),
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

        // === COMISARÍA MÁS CERCANA (solo idle) ===
        if (!_isCountingDown && !_isActivated)
          _buildNearestStationCard(),

        // === UBICACIÓN INFO ===
        if (!_isCountingDown && !_isActivated)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Icon(Icons.location_on,
                    color: Colors.white.withValues(alpha: 0.6), size: 20),
                const SizedBox(height: 4),
                Text(
                  _isLocating
                      ? 'Obteniendo ubicación...'
                      : 'Se compartirá tu ubicación GPS exacta',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                if (_userAddress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _userAddress!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ============================================================
  // VISTA ACTIVADA (ALERTA ENVIADA)
  // ============================================================
  Widget _buildActivatedView(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // === HEADER: ALERTA ENVIADA ===
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                // Icono pulso
                AnimatedBuilder(
                  animation: _mapBlinkController,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withValues(alpha: 0.1 + _mapBlinkController.value * 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  '🚨 ¡ALERTA ENVIADA!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tu ubicación ha sido compartida\ncon la red vecinal de Collique',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
                if (_saveError)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
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
              ],
            ),
          ),

          const SizedBox(height: 16),

          // === MINI-MAPA con ubicación pulsante ===
          _buildMiniMap(isDark),

          const SizedBox(height: 16),

          // === UBICACIÓN ACTUAL ===
          if (_userLat != null || _userAddress != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tu ubicación actual',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        if (_userAddress != null)
                          Text(
                            _userAddress!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (_userLat != null)
                          Text(
                            '${_userLat!.toStringAsFixed(4)}, ${_userLng!.toStringAsFixed(4)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // === COMISARÍA MÁS CERCANA (versión grande) ===
          _buildNearestStationCard(large: true),

          const SizedBox(height: 12),

          // === BOTÓN COMPARTIR POR WHATSAPP ===
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF25D366).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Compartir por WhatsApp',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Envía tu ubicación a tus contactos',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _sendWhatsAppLocation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF25D366).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.send_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'ENVIAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // === TELÉFONO DE EMERGENCIA NACIONAL ===
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.phone, color: Colors.amber, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Emergencia Nacional',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Policía: 105 | Serenazgo: 116 | Bomberos: 116',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _callEmergeny('105'),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'LLAMAR',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // === BOTÓN DESACTIVAR ===
          ElevatedButton.icon(
            onPressed: _deactivateAlert,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: const Text(
              'DESACTIVAR ALERTA',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF212121),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // === CARGANDO (si alerta no enviada aún) ===
          if (!_alertSent)
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // MINI-MAPA CON UBICACIÓN PULSANTE
  // ============================================================
  Widget _buildMiniMap(bool isDark) {
    final lat = _userLat ?? LocationService.colliqueLat;
    final lng = _userLng ?? LocationService.colliqueLng;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
        ),
        child: Stack(
          children: [
            // Mapa
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: MapConfig.colliqueBounds.contains(LatLng(lat, lng))
                    ? LatLng(lat, lng)
                    : MapConfig.colliqueCenter,
                initialZoom: 16.0,
                minZoom: 14.0,
                maxZoom: 17.0,
                backgroundColor: const Color(0xFFE8ECEF),
                cameraConstraint: MapConfig.colliqueConstraint,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: isDark
                      ? MapConfig.darkTileUrl
                      : MapConfig.lightTileUrl,
                  userAgentPackageName: 'com.safezone.app',
                ),

                // Marcador de ubicación del usuario con parpadeo
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(lat, lng),
                      width: 80,
                      height: 80,
                      child: AnimatedBuilder(
                        animation: _mapBlinkController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Anillo pulsante exterior
                              Container(
                                width: 60 + _mapBlinkController.value * 20,
                                height: 60 + _mapBlinkController.value * 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red
                                      .withValues(alpha: 0.2 * (1 - _mapBlinkController.value * 0.5)),
                                ),
                              ),
                              // Anillo medio
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red
                                      .withValues(alpha: 0.4 * _mapBlinkOpacity.value),
                                ),
                              ),
                              // Punto central
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFFF1744),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF1744)
                                          .withValues(alpha: 0.6),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Overlay "TÚ ESTÁS AQUÍ"
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_pin_circle,
                        color: Color(0xFFFF1744), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Tú estás aquí',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Indicador de peligro
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF1744).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AnimatedBuilder(
                  animation: _mapBlinkController,
                  builder: (context, child) {
                    return Text(
                      '🚨 PELIGRO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TARJETA DE COMISARÍA MÁS CERCANA
  // ============================================================
  Widget _buildNearestStationCard({bool large = false}) {
    if (_nearestStation == null) {
      return const SizedBox.shrink();
    }

    final station = _nearestStation!;
    final name = station['name'] as String;
    final phone = station['phone'] as String;
    final emergencyPhone = station['emergency_phone'] as String;
    final type = station['type'] as String;

    final typeLabel = switch (type) {
      'comisaria' => 'Comisaría',
      'puesto' => 'Puesto Policial',
      'serenazgo' => 'Serenazgo',
      _ => 'Punto de seguridad',
    };

    final typeIcon = switch (type) {
      'comisaria' => Icons.local_police,
      'puesto' => Icons.security,
      'serenazgo' => Icons.directions_walk,
      _ => Icons.location_on,
    };

    final containerWidth = large ? null : 300.0;

    return Container(
      width: containerWidth,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(typeIcon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Distancia badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.near_me,
                        size: 12, color: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 3),
                    Text(
                      _distanceText,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Teléfonos y botón llamar
          Row(
            children: [
              // Teléfono
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.phone_in_talk,
                        size: 14, color: Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Botón LLAMAR
              if (large)
                GestureDetector(
                  onTap: () => _callEmergeny(emergencyPhone),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'LLAMAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _callEmergeny(emergencyPhone),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'LLAMAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
