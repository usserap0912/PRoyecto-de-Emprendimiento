import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/location_service.dart';

class RiskMapScreen extends StatefulWidget {
  final String userCode;

  const RiskMapScreen({super.key, required this.userCode});

  @override
  State<RiskMapScreen> createState() => _RiskMapScreenState();
}

class _RiskMapScreenState extends State<RiskMapScreen>
    with SingleTickerProviderStateMixin {
  bool _walkWithMe = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  final MapController _mapController = MapController();

  // Puntos de peligro de ejemplo en Collique
  final List<_DangerPin> _dangerPins = [
    _DangerPin(
      lat: -11.9320,
      lng: -77.0730,
      title: 'Falta de alumbrado',
      description: 'Pasaje a oscuras, poste de luz malogrado',
      severity: 2,
    ),
    _DangerPin(
      lat: -11.9335,
      lng: -77.0745,
      title: 'Zona de riesgo',
      description: 'Reportes de robos en la última semana',
      severity: 3,
    ),
    _DangerPin(
      lat: -11.9310,
      lng: -77.0715,
      title: 'Sospechoso frecuente',
      description: 'Moto negra merodeando por las noches',
      severity: 2,
    ),
    _DangerPin(
      lat: -11.9345,
      lng: -77.0760,
      title: 'Zona segura',
      description: 'Serenazgo patrulla cada 30 minutos',
      severity: 1,
    ),
    _DangerPin(
      lat: -11.9305,
      lng: -77.0700,
      title: 'Alarma vecinal',
      description: 'Vecinos organizados, ronda nocturna activa',
      severity: 1,
    ),
  ];

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
      case 3:
        return AppTheme.dangerRed;
      case 2:
        return AppTheme.warningYellow;
      case 1:
        return AppTheme.safeGreen;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Riesgo'),
        actions: [
          // Walk With Me button in appbar
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return GestureDetector(
                onTap: () => setState(() => _walkWithMe = !_walkWithMe),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _walkWithMe
                        ? Colors.greenAccent.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: _walkWithMe ? Colors.greenAccent : Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: _walkWithMe
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withValues(alpha: 0.5),
                              blurRadius: 15,
                              spreadRadius: _pulseAnim.value * 3,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.directions_walk,
                        size: 18,
                        color: _walkWithMe ? Colors.black87 : Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _walkWithMe ? 'Camino Contigo' : 'Camina Conmigo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _walkWithMe ? Colors.black87 : Colors.white,
                        ),
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
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(
                LocationService.colliqueLat,
                LocationService.colliqueLng,
              ),
              initialZoom: 15.0,
              minZoom: 13.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.safezone.app',
              ),
              // Danger pin markers
              MarkerLayer(
                markers: _dangerPins.map((pin) {
                  return Marker(
                    point: LatLng(pin.lat, pin.lng),
                    width: 120,
                    height: 50,
                    child: _DangerPinWidget(
                      pin: pin,
                      color: _getSeverityColor(pin.severity),
                    ),
                  );
                }).toList(),
              ),
              // Walk With Me marker
              if (_walkWithMe)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        LocationService.colliqueLat + 0.002,
                        LocationService.colliqueLng + 0.001,
                      ),
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
                                border: Border.all(
                                  color: Colors.greenAccent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.greenAccent.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.directions_walk,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Legend overlay
          Positioned(
            left: 12,
            bottom: 24,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Leyenda',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _LegendItem(color: AppTheme.dangerRed, label: 'Peligro Alto'),
                    const SizedBox(height: 4),
                    _LegendItem(color: AppTheme.warningYellow, label: 'Precaución'),
                    const SizedBox(height: 4),
                    _LegendItem(color: AppTheme.safeGreen, label: 'Zona Segura'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerPin {
  final double lat;
  final double lng;
  final String title;
  final String description;
  final int severity; // 1=seguro, 2=precaución, 3=peligro

  _DangerPin({
    required this.lat,
    required this.lng,
    required this.title,
    required this.description,
    required this.severity,
  });
}

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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.pin.title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.pin.description,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              widget.pin.severity == 3
                  ? Icons.warning
                  : widget.pin.severity == 2
                      ? Icons.info_outline
                      : Icons.check,
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
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
