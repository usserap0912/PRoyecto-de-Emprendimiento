import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:safezone/config/map_config.dart';
import 'package:safezone/models/sos_session.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/services/permission_service.dart';
import 'package:safezone/services/sos_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class SosScreen extends StatefulWidget {
  final String userCode;
  final int zone;
  final SosService? service;

  const SosScreen({
    super.key,
    required this.userCode,
    required this.zone,
    this.service,
  });

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with TickerProviderStateMixin {
  late final SosService _sosService;
  final SoundService _soundService = SoundService();
  final LocationService _locationService = LocationService();
  final PermissionService _permissionService = PermissionService();
  final MapController _mapController = MapController();

  late final AnimationController _buttonPulseController;
  late final Animation<double> _buttonPulseScale;
  late final AnimationController _mapPulseController;

  Timer? _activationTimer;
  StreamSubscription<Position>? _positionSubscription;
  bool _isPreparing = false;
  bool _isCountingDown = false;
  int _activationCountdown = 3;
  double? _userLat;
  double? _userLng;
  Map<String, dynamic>? _nearestStation;
  String? _distanceText;

  @override
  void initState() {
    super.initState();
    _sosService = widget.service ?? SosService();
    _buttonPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _buttonPulseScale = Tween<double>(begin: 1, end: 1.04).animate(
      CurvedAnimation(parent: _buttonPulseController, curve: Curves.easeInOut),
    );
    _mapPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _sosService.state.addListener(_onSosStateChanged);
    _onSosStateChanged();
  }

  @override
  void dispose() {
    _activationTimer?.cancel();
    _positionSubscription?.cancel();
    _sosService.state.removeListener(_onSosStateChanged);
    unawaited(_soundService.stopSosActivationAlarm());
    _buttonPulseController.dispose();
    _mapPulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSosStateChanged() {
    final session = _sosService.state.value;
    if (session.isActive) {
      unawaited(_soundService.startSosActivationAlarm());
      _buttonPulseController.stop();
      if (!_mapPulseController.isAnimating) {
        _mapPulseController.repeat(reverse: true);
      }
    } else if (session.phase == SosSessionPhase.idle) {
      unawaited(_soundService.stopSosActivationAlarm());
      _mapPulseController.stop();
      _mapPulseController.value = 0;
      if (!_buttonPulseController.isAnimating) {
        _buttonPulseController.repeat(reverse: true);
      }
    } else {
      unawaited(_soundService.stopSosActivationAlarm());
      _buttonPulseController.stop();
      _mapPulseController.stop();
    }
    if (!session.isActive) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _userLat = null;
      _userLng = null;
      _nearestStation = null;
      _distanceText = null;
    }
  }

  Future<void> _beginActivation() async {
    if (_isPreparing || _isCountingDown || _sosService.isActive) return;
    _safeHaptic(HapticFeedback.heavyImpact);
    setState(() => _isPreparing = true);

    final hasLocation = await _prepareLocationPermission();
    if (hasLocation) await _loadCurrentLocation();
    if (!mounted) return;

    setState(() {
      _isPreparing = false;
      _isCountingDown = true;
      _activationCountdown = 3;
    });
    _activationTimer?.cancel();
    _activationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      _safeHaptic(HapticFeedback.mediumImpact);
      setState(() => _activationCountdown--);
      if (_activationCountdown <= 0) {
        timer.cancel();
        unawaited(_activateSos());
      }
    });
  }

  Future<bool> _prepareLocationPermission() async {
    if (await _permissionService.hasLocationPermission()) return true;
    if (!mounted) return false;

    final shouldRequest =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Ubicación durante el S.O.S.'),
            content: const Text(
              'SafeZone usará tu GPS únicamente mientras la alerta esté activa. '
              'Compartirá una ubicación aproximada con usuarios conectados y la '
              'retirará al finalizar. Si no autorizas, el S.O.S. funcionará solo '
              'en este dispositivo y podrás llamar a emergencias.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Continuar sin GPS'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Permitir ubicación'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldRequest) return false;

    final result = await _permissionService.requestLocationPermission();
    if (result == AppPermissionResult.granted) return true;
    if (!mounted) return false;

    final message = switch (result) {
      AppPermissionResult.permanentlyDenied =>
        'Ubicación bloqueada. Puedes habilitarla en Configuración; el S.O.S. seguirá local.',
      AppPermissionResult.unavailable =>
        'El GPS no está disponible. El S.O.S. seguirá local.',
      _ => 'Permiso denegado. El S.O.S. seguirá local.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
    return false;
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (position == null || !mounted) return;
      _setLocalPosition(position.latitude, position.longitude);
    } catch (error) {
      debugPrint('SosScreen location error: $error');
    }
  }

  void _setLocalPosition(double latitude, double longitude) {
    if (!mounted) return;
    final station = LocationService.findNearestStation(latitude, longitude);
    final distance = station['distance_meters'] as double;
    setState(() {
      _userLat = latitude;
      _userLng = longitude;
      _nearestStation = station;
      _distanceText = LocationService.formatDistance(distance);
    });
  }

  Future<void> _activateSos() async {
    if (!mounted) return;
    setState(() => _isCountingDown = false);
    _safeHaptic(HapticFeedback.heavyImpact);

    final coordinates = _userLat != null && _userLng != null
        ? SosCoordinates(latitude: _userLat!, longitude: _userLng!)
        : null;
    unawaited(
      _sosService.activate(
        userCode: widget.userCode,
        zone: widget.zone,
        coordinates: coordinates,
      ),
    );
    if (coordinates != null) _startPositionSharing();
  }

  void _startPositionSharing() {
    _positionSubscription?.cancel();
    final stream = _locationService.getPositionStream();
    if (stream == null) return;
    _positionSubscription = stream.listen(
      (position) {
        if (!_sosService.isActive) return;
        _setLocalPosition(position.latitude, position.longitude);
        unawaited(
          _sosService.updateLocation(
            SosCoordinates(
              latitude: position.latitude,
              longitude: position.longitude,
            ),
          ),
        );
      },
      onError: (Object error) {
        debugPrint('SosScreen position stream error: $error');
      },
    );
  }

  void _cancelActivationCountdown() {
    _activationTimer?.cancel();
    _safeHaptic(HapticFeedback.lightImpact);
    setState(() {
      _isCountingDown = false;
      _activationCountdown = 3;
      _isPreparing = false;
    });
  }

  Future<void> _retrySosTransmission() async {
    if (_userLat == null || _userLng == null) {
      if (!await _prepareLocationPermission()) return;
      await _loadCurrentLocation();
      if (_userLat == null || _userLng == null) return;
      _startPositionSharing();
      await _sosService.updateLocation(
        SosCoordinates(latitude: _userLat!, longitude: _userLng!),
      );
      return;
    }
    await _sosService.retry();
  }

  Future<void> _confirmAndCancel() async {
    if (!_sosService.state.value.canCancel || !mounted) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Finalizar S.O.S.?'),
            content: const Text(
              'La ubicación dejará de compartirse y los demás usuarios verán la alerta como finalizada.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Mantener activo'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Finalizar'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await _sosService.cancel();
  }

  Future<void> _callEmergency(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (error) {
      debugPrint('SosScreen phone launch error: $error');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Este dispositivo no puede iniciar llamadas. Marca $phone.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareLocation() async {
    if (!_sosService.isActive || _userLat == null || _userLng == null) return;
    final mapsUrl = 'https://maps.google.com/maps?q=$_userLat,$_userLng';
    final message = Uri.encodeComponent(
      '🚨 Necesito ayuda urgente. Mi ubicación actual: $mapsUrl',
    );
    final nativeUri = Uri.parse('whatsapp://send?text=$message');
    final webUri = Uri.parse('https://wa.me/?text=$message');
    try {
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      debugPrint('SosScreen share error: $error');
    }
  }

  void _safeHaptic(Future<void> Function() feedback) {
    try {
      unawaited(feedback());
    } catch (_) {
      // Web and devices without a vibration implementation keep working.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('S.O.S.'),
        backgroundColor: AppTheme.sosRed,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.sosRed, AppTheme.sosDarkRed],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ValueListenableBuilder<SosSessionState>(
            valueListenable: _sosService.state,
            builder: (context, session, _) => switch (session.phase) {
              SosSessionPhase.idle => _buildIdle(),
              SosSessionPhase.activeLocked ||
              SosSessionPhase.activeCanCancel => _buildActive(session),
              SosSessionPhase.finished => _buildFinished(session),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIdle() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          const Icon(Icons.shield_outlined, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          const Text(
            '¿Estás en peligro?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isCountingDown
                ? 'La alerta se activará en $_activationCountdown'
                : _isPreparing
                ? 'Preparando ubicación…'
                : 'Mantén la calma. SafeZone compartirá tu ubicación solo durante 60 segundos.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const Spacer(),
          if (_isCountingDown)
            _CountdownButton(
              seconds: _activationCountdown,
              onCancel: _cancelActivationCountdown,
            )
          else
            ScaleTransition(
              scale: _buttonPulseScale,
              child: Semantics(
                button: true,
                label: 'Activar alerta S.O.S.',
                child: GestureDetector(
                  onTap: _isPreparing ? null : _beginActivation,
                  onLongPress: _isPreparing ? null : _beginActivation,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 8),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: _isPreparing
                        ? const Center(child: CircularProgressIndicator())
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sos, color: AppTheme.sosRed, size: 68),
                              Text(
                                'ACTIVAR',
                                style: TextStyle(
                                  color: AppTheme.sosRed,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          const _PrivacyNote(),
          const SizedBox(height: 12),
          _EmergencyContacts(onCall: _callEmergency),
        ],
      ),
    );
  }

  Widget _buildActive(SosSessionState session) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'ALERTA S.O.S. ACTIVA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            _RemainingBadge(seconds: session.remainingSeconds),
          ],
        ),
        const SizedBox(height: 14),
        _TransmissionCard(session: session, onRetry: _retrySosTransmission),
        const SizedBox(height: 14),
        if (_userLat != null && _userLng != null) ...[
          _buildMiniMap(),
          const SizedBox(height: 12),
          const _PrivacyNote(),
        ] else
          const _NoLocationCard(),
        if (_nearestStation != null) ...[
          const SizedBox(height: 12),
          _buildNearestStationCard(),
        ],
        const SizedBox(height: 14),
        _EmergencyContacts(onCall: _callEmergency),
        if (_userLat != null && _userLng != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _shareLocation,
            icon: const Icon(Icons.share_location),
            label: const Text('Compartir mi ubicación por WhatsApp'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Builder(
          builder: (context) {
            final lockedFor = (30 - session.elapsedSeconds).clamp(0, 30);
            return Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: session.canCancel ? _confirmAndCancel : null,
                    icon: Icon(
                      session.canCancel ? Icons.stop_circle : Icons.lock_clock,
                    ),
                    label: Text(
                      session.canCancel
                          ? 'FINALIZAR ALERTA (${session.remainingSeconds} s)'
                          : 'PROTECCIÓN ACTIVA · $lockedFor s',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black87,
                      disabledBackgroundColor: Colors.black38,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  session.canCancel
                      ? 'Puedes finalizarla ahora. Si no haces nada, terminará automáticamente.'
                      : 'Durante los primeros 30 segundos no puede cancelarse accidentalmente.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFinished(SosSessionState session) {
    final retryNeeded =
        session.transmissionStatus == SosTransmissionStatus.failed &&
        session.alertId != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              retryNeeded ? Icons.cloud_off : Icons.check_circle_outline,
              color: Colors.white,
              size: 76,
            ),
            const SizedBox(height: 16),
            const Text(
              'S.O.S. finalizado',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              session.message ?? 'La ubicación dejó de compartirse.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (retryNeeded) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _sosService.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar cierre'),
              ),
            ],
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: retryNeeded ? null : _sosService.reset,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMap() {
    final point = LatLng(_userLat!, _userLng!);
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: point,
            initialZoom: 16,
            minZoom: 11,
            maxZoom: 21,
            cameraConstraint: const CameraConstraint.unconstrained(),
          ),
          children: [
            TileLayer(
              urlTemplate: MapConfig.lightTileUrl,
              userAgentPackageName: 'com.safezone.app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 82,
                  height: 82,
                  child: AnimatedBuilder(
                    animation: _mapPulseController,
                    builder: (context, _) {
                      final value = _mapPulseController.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 48 + value * 24,
                            height: 48 + value * 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.sosRed.withValues(
                                alpha: 0.32 * (1 - value),
                              ),
                            ),
                          ),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppTheme.sosRed,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(Icons.sos, color: Colors.white),
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
      ),
    );
  }

  Widget _buildNearestStationCard() {
    final station = _nearestStation!;
    final emergencyPhone = station['emergency_phone'] as String? ?? '105';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_police, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comisaría verificada más cercana',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  station['name'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _distanceText ?? '',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: () => _callEmergency(emergencyPhone),
            icon: const Icon(Icons.call),
            tooltip: 'Llamar al $emergencyPhone',
          ),
        ],
      ),
    );
  }
}

class _CountdownButton extends StatelessWidget {
  final int seconds;
  final VoidCallback onCancel;

  const _CountdownButton({required this.seconds, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$seconds',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 100,
            fontWeight: FontWeight.w900,
          ),
        ),
        OutlinedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          label: const Text('Cancelar activación'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white54),
          ),
        ),
      ],
    );
  }
}

class _RemainingBadge extends StatelessWidget {
  final int seconds;

  const _RemainingBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white70, width: 3),
      ),
      child: Text(
        '$seconds',
        style: const TextStyle(
          color: AppTheme.sosRed,
          fontWeight: FontWeight.w900,
          fontSize: 22,
        ),
      ),
    );
  }
}

class _TransmissionCard extends StatelessWidget {
  final SosSessionState session;
  final Future<void> Function() onRetry;

  const _TransmissionCard({required this.session, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final failed = session.transmissionStatus == SosTransmissionStatus.failed;
    final sending = session.transmissionStatus == SosTransmissionStatus.sending;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: failed ? Colors.amber : Colors.white24),
      ),
      child: Row(
        children: [
          if (sending)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            Icon(
              failed ? Icons.cloud_off : Icons.cloud_done,
              color: failed ? Colors.amber : Colors.white,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              session.message ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          if (failed && session.isActive)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: Colors.amber),
              child: const Text('Reintentar'),
            ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline, color: Colors.white70, size: 16),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'La ubicación no se conserva públicamente al finalizar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _NoLocationCard extends StatelessWidget {
  const _NoLocationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber),
      ),
      child: const Row(
        children: [
          Icon(Icons.location_off, color: Colors.amber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin GPS: no se ha compartido ninguna coordenada. Usa los botones de llamada.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyContacts extends StatelessWidget {
  final Future<void> Function(String phone) onCall;

  const _EmergencyContacts({required this.onCall});

  static const contacts = <({String label, String phone, IconData icon})>[
    (label: 'Policía', phone: '105', icon: Icons.local_police),
    (label: 'SAMU', phone: '106', icon: Icons.medical_services),
    (label: 'Bomberos', phone: '116', icon: Icons.fire_truck),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Emergencias oficiales del Perú',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: contacts
                .map(
                  (contact) => ActionChip(
                    avatar: Icon(contact.icon, size: 18),
                    label: Text('${contact.label} ${contact.phone}'),
                    onPressed: () => onCall(contact.phone),
                  ),
                )
                .toList(growable: false),
          ),
          const Divider(height: 22, color: Colors.white24),
          const Text(
            'Dependencias PNP verificadas en Collique',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final station in LocationService.policeStations)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_outlined,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${station['name']} · sin teléfono directo verificado',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
