import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/screens/games/games_hub_screen.dart';

class RiskMapScreen extends StatefulWidget {
  final String userCode;

  const RiskMapScreen({super.key, required this.userCode});

  @override
  State<RiskMapScreen> createState() => _RiskMapScreenState();
}

class _RiskMapScreenState extends State<RiskMapScreen>
    with SingleTickerProviderStateMixin {
  bool _walkWithMe = false;
  bool _useDarkStyle = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  final MapController _mapController = MapController();

  // Límites estrictos para las 14 zonas de Collique
  static final LatLngBounds _colliqueBounds = LatLngBounds(
    const LatLng(-11.949, -77.090), // Suroeste (zona 14)
    const LatLng(-11.924, -77.064), // Noreste (zona 1 / Museo)
  );

  // Puntos de referencia reales en Collique
  static const _Landmark hospital = _Landmark(
    name: 'Hospital Sergio Bernales',
    lat: -11.9312, lng: -77.0698,
    icon: Icons.local_hospital,
    color: Color(0xFFE53935),
    description: 'Principal centro de salud de Collique, atiende emergencias 24h.',
  );

  static const _Landmark comisaria = _Landmark(
    name: 'Comisaría de Collique',
    lat: -11.9335, lng: -77.0730,
    icon: Icons.local_police,
    color: Color(0xFF1565C0),
    description: 'Comisaría sectorial al servicio de las zonas de Collique.',
  );

  static const _Landmark museo = _Landmark(
    name: 'Museo de los Colli',
    lat: -11.9265, lng: -77.0665,
    icon: Icons.museum,
    color: Color(0xFFF9A825),
    description: 'Fortaleza y sitio arqueológico de la Cultura Colli.',
  );

  // Puntos de peligro en Collique
  final List<_DangerPin> _dangerPins = [
    _DangerPin(lat: -11.9320, lng: -77.0730, title: '🚨 Zona de Riesgo - 3ra Zona', description: 'Reportes de robos frecuentes en horas nocturnas.', severity: 3),
    _DangerPin(lat: -11.9380, lng: -77.0795, title: '⚠️ Falta de Alumbrado - Zona 9', description: 'Pasajes oscuros en sector alto.', severity: 2),
    _DangerPin(lat: -11.9415, lng: -77.0825, title: '🔴 Riesgo Alto - Zona 11', description: 'Zona alta con merodeo sospechoso.', severity: 3),
    _DangerPin(lat: -11.9445, lng: -77.0850, title: '⚠️ Precaución - Zona 14', description: 'Sector alto. Circular en grupo recomendado.', severity: 2),
    _DangerPin(lat: -11.9295, lng: -77.0695, title: '✅ Zona Segura - 1ra Zona', description: 'Serenazgo patrulla cada 30 min.', severity: 1),
    _DangerPin(lat: -11.9350, lng: -77.0750, title: '✅ Zona Vigilada - 4ta Zona', description: 'Cámaras vecinales activas.', severity: 1),
    _DangerPin(lat: -11.9365, lng: -77.0785, title: '⚠️ Precaución - Zona 8', description: 'Moto reportada merodeando.', severity: 2),
    _DangerPin(lat: -11.9430, lng: -77.0838, title: '🔴 Riesgo Alto - Zona 13', description: 'Zona alta, poca iluminación.', severity: 3),
  ];

  // URLs CartoDB para los estilos
  static const String _cartoDbPositronUrl =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  static const String _cartoDbDarkUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  String get _currentTileUrl =>
      _useDarkStyle ? _cartoDbDarkUrl : _cartoDbPositronUrl;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Color _getSeverityColor(int severity) {
    switch (severity) {
      case 3: return AppTheme.dangerRed;
      case 2: return AppTheme.warningYellow;
      case 1: return AppTheme.safeGreen;
      default: return Colors.grey;
    }
  }

  void _toggleStyle() => setState(() => _useDarkStyle = !_useDarkStyle);

  void _goToGames() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GamesHubScreen(
          userCode: widget.userCode,
          zone: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Collique'),
        actions: [
          // Walk With Me button
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return GestureDetector(
                onTap: () => setState(() => _walkWithMe = !_walkWithMe),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _walkWithMe ? Colors.greenAccent.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: _walkWithMe ? Colors.greenAccent : Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: _walkWithMe ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.5), blurRadius: 15, spreadRadius: _pulseAnim.value * 3)] : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_walk, size: 16, color: _walkWithMe ? Colors.black87 : Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        _walkWithMe ? 'Camino Contigo' : 'Camina Conmigo',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _walkWithMe ? Colors.black87 : Colors.white),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // === MAPA PRINCIPAL ===
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-11.9325, -77.0734),
              initialZoom: 15.0,
              minZoom: 14.5,
              maxZoom: 17.0,
              cameraConstraint: CameraConstraint.contain(
                bounds: _colliqueBounds,
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // TileLayer con CartoDB
              TileLayer(
                urlTemplate: _currentTileUrl,
                userAgentPackageName: 'com.safezone.app',
              ),

              // === MARCADORES DE ZONAS (1-14) ===
              MarkerLayer(
                markers: [
                  for (int i = 1; i <= 14; i++)
                    _buildZoneMarker(i, isDark),
                ],
              ),

              // === MARCADORES DE PUNTOS DE REFERENCIA ===
              MarkerLayer(
                markers: [
                  _buildLandmarkMarker(hospital),
                  _buildLandmarkMarker(comisaria),
                  _buildLandmarkMarker(museo),
                ],
              ),

              // === MARCADORES DE PELIGRO ===
              MarkerLayer(
                markers: _dangerPins.map((pin) {
                  return Marker(
                    point: LatLng(pin.lat, pin.lng),
                    width: 100,
                    height: 45,
                    child: _DangerPinWidget(pin: pin, color: _getSeverityColor(pin.severity)),
                  );
                }).toList(),
              ),

              // === MARCADOR DE "WALK WITH ME" ===
              if (_walkWithMe)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(LocationService.colliqueLat + 0.002, LocationService.colliqueLng + 0.001),
                      width: 80,
                      height: 80,
                      child: AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnim.value,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.greenAccent, width: 3),
                                boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5)],
                              ),
                              child: const Center(child: Icon(Icons.directions_walk, color: Colors.white, size: 30)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // === LEYENDA ===
          Positioned(
            left: 12,
            bottom: 80,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Leyenda', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    _LegendItem(color: AppTheme.dangerRed, label: 'Peligro Alto'),
                    const SizedBox(height: 3),
                    _LegendItem(color: AppTheme.warningYellow, label: 'Precaución'),
                    const SizedBox(height: 3),
                    _LegendItem(color: AppTheme.safeGreen, label: 'Zona Segura'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFF1565C0), label: 'Comisaría'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFFE53935), label: 'Hospital'),
                    const SizedBox(height: 3),
                    _LegendItem(color: const Color(0xFFF9A825), label: 'Museo'),
                  ],
                ),
              ),
            ),
          ),

          // === BOTÓN FLOTANTE: ESTILO DE MAPA ===
          Positioned(
            right: 16,
            top: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'style_toggle',
                  onPressed: _toggleStyle,
                  backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.75),
                  child: Icon(
                    _useDarkStyle ? Icons.light_mode : Icons.dark_mode,
                    color: isDark ? Colors.black87 : Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _useDarkStyle ? 'Oscuro' : 'Claro',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? Colors.black87 : Colors.white),
                  ),
                ),
              ],
            ),
          ),

          // === BOTÓN FLOTANTE: IR A JUEGOS ===
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Juegos', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(height: 4),
                FloatingActionButton(
                  heroTag: 'go_to_games',
                  onPressed: _goToGames,
                  backgroundColor: AppTheme.primaryGreen,
                  child: const Icon(Icons.sports_esports, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Marker _buildZoneMarker(int zoneNumber, bool isDark) {
    final coords = LocationService.zoneCoordinates[zoneNumber];
    if (coords == null) {
      return Marker(point: LatLng(0, 0), width: 0, height: 0, child: const SizedBox.shrink());
    }

    return Marker(
      point: LatLng(coords['lat']!, coords['lng']!),
      width: 60,
      height: 30,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Text(
          'Z$zoneNumber',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Marker _buildLandmarkMarker(_Landmark landmark) {
    return Marker(
      point: LatLng(landmark.lat, landmark.lng),
      width: 120,
      height: 60,
      child: _LandmarkWidget(
        name: landmark.name,
        icon: landmark.icon,
        color: landmark.color,
        description: landmark.description,
      ),
    );
  }
}

// ============================================================
// Modelos
// ============================================================

class _Landmark {
  final String name;
  final double lat;
  final double lng;
  final IconData icon;
  final Color color;
  final String description;
  const _Landmark({
    required this.name,
    required this.lat,
    required this.lng,
    required this.icon,
    required this.color,
    required this.description,
  });
}

class _DangerPin {
  final double lat;
  final double lng;
  final String title;
  final String description;
  final int severity;
  _DangerPin({
    required this.lat,
    required this.lng,
    required this.title,
    required this.description,
    required this.severity,
  });
}

// ============================================================
// Widgets
// ============================================================

/// Marcador interactivo de punto de referencia
class _LandmarkWidget extends StatefulWidget {
  final String name;
  final IconData icon;
  final Color color;
  final String description;
  const _LandmarkWidget({
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
  });

  @override
  State<_LandmarkWidget> createState() => _LandmarkWidgetState();
}

class _LandmarkWidgetState extends State<_LandmarkWidget>
    with SingleTickerProviderStateMixin {
  bool _showInfo = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _showInfo = !_showInfo),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showInfo)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(widget.description, style: TextStyle(fontSize: 9, color: Colors.grey[600]), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return Transform.scale(
                scale: _showInfo ? 1.15 : _pulseAnim.value,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)],
                  ),
                  child: Icon(widget.icon, size: 22, color: Colors.white),
                ),
              );
            },
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
            child: Text(
              widget.name,
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Marcador interactivo de punto de peligro
class _DangerPinWidget extends StatefulWidget {
  final _DangerPin pin;
  final Color color;
  const _DangerPinWidget({required this.pin, required this.color});

  @override
  State<_DangerPinWidget> createState() => _DangerPinWidgetState();
}

class _DangerPinWidgetState extends State<_DangerPinWidget> {
  bool _showInfo = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _showInfo = !_showInfo),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showInfo)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.pin.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(widget.pin.description, style: TextStyle(fontSize: 10, color: Colors.grey[600]), textAlign: TextAlign.center),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)],
            ),
            child: Icon(
              widget.pin.severity == 3 ? Icons.warning : widget.pin.severity == 2 ? Icons.info_outline : Icons.check,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}
