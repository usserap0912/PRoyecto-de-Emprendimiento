import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/screens/games/games_hub_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

class RiskMapScreen extends StatefulWidget {
  final String userCode;

  const RiskMapScreen({super.key, required this.userCode});

  @override
  State<RiskMapScreen> createState() => _RiskMapScreenState();
}

class _RiskMapScreenState extends State<RiskMapScreen> {
  bool _useDarkStyle = false;
  final SupabaseService _supabase = SupabaseService();
  final MapController _mapController = MapController();
  // Reportes en tiempo real vía stream de Supabase
  List<Map<String, dynamic>> _reports = [];
  StreamSubscription<List<Map<String, dynamic>>>? _reportsSubscription;
  bool _isLoading = true;

  // Límites de Collique
  static final LatLngBounds _colliqueBounds = LatLngBounds(
    const LatLng(-11.949, -77.090),
    const LatLng(-11.918, -77.025),
  );

  // URLs CartoDB
  static const String _cartoDbPositronUrl =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  static const String _cartoDbDarkUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  String get _currentTileUrl =>
      _useDarkStyle ? _cartoDbDarkUrl : _cartoDbPositronUrl;

  // ================================================================
  // INICIALIZACIÓN
  // ================================================================
  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('es', timeago.EsMessages());
    _initReportsStream();
  }

  @override
  void dispose() {
    _reportsSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ================================================================
  // SUPABASE: STREAM EN VIVO DE REPORTES
  // ================================================================
  /// Escucha la tabla 'reports' en tiempo real usando el stream nativo de Supabase.
  /// Se actualiza automáticamente con inserts, updates y deletes.
  void _initReportsStream() {
    try {
      _reportsSubscription = _supabase.client
          .from('reports')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .listen(
        (List<Map<String, dynamic>> data) {
          if (mounted) {
            setState(() {
              _reports = data;
              _isLoading = false;
            });
          }
        },
        onError: (Object error) {
          debugPrint('Error en stream de reportes: $error');
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } catch (e) {
      debugPrint('Error iniciando stream de reportes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================================================================
  // COLOR SEGÚN CATEGORÍA DEL REPORTE
  // ================================================================
  Color _colorPorCategoria(String? category) {
    switch (category) {
      case 'robo':
        return const Color(0xFFFF0000); // Rojo
      case 'sospechoso':
        return const Color(0xFFFFA500); // Naranja
      case 'extorsion':
        return const Color(0xFFFFA500); // Naranja (similar a sospechoso)
      case 'alumbrado':
        return const Color(0xFFFFFF00); // Amarillo
      default:
        return Colors.grey;
    }
  }

  // ================================================================
  // COLOR SEGÚN ANTIGÜEDAD DEL REPORTE
  // ================================================================
  Color _colorPorAntiguedad(String? createdAtStr) {
    final createdAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr)
        : null;
    if (createdAt == null) return Colors.grey;

    final now = DateTime.now();
    final difference = now.difference(createdAt);

    // 0 a 12 horas → Rojo
    if (difference.inHours <= 12) {
      return const Color(0xFFFF0000);
    }
    // 2 a 6 días → Amarillo
    if (difference.inDays >= 2 && difference.inDays <= 6) {
      return const Color(0xFFFFFF00);
    }
    // 7 días o más → Azul
    if (difference.inDays >= 7) {
      return const Color(0xFF0000FF);
    }
    // Entre 12h y 2d → Naranja (transición)
    return const Color(0xFFFFA500);
  }

  // ================================================================
  // CONSTRUIR MARCADORES
  // ================================================================
  List<Marker> _construirMarcadores() {
    return _reports.map((report) {
      final lat = (report['lat'] ?? report['latitude']) as num?;
      final lng = (report['lng'] ?? report['longitude']) as num?;
      if (lat == null || lng == null) {
        return Marker(
          point: const LatLng(0, 0),
          width: 0,
          height: 0,
          child: const SizedBox.shrink(),
        );
      }

      // Color por categoría en lugar de risk level
      final category = report['category'] as String?;
      final color = _colorPorCategoria(category);

      return Marker(
        point: LatLng(lat.toDouble(), lng.toDouble()),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _mostrarBottomSheet(report),
          child: _MarkerPin(color: color, category: category),
        ),
      );
    }).toList();
  }

  // ================================================================
  // BOTTOM SHEET DE DETALLE
  // ================================================================
  void _mostrarBottomSheet(Map<String, dynamic> report) {
    final zoneNumber = report['zone_number'] ?? report['zone'];
    final riskLevel = report['risk_level'] as String? ?? 'baja';
    final category = report['category'] as String? ?? 'otros';
    final description = report['description'] as String? ?? '';
    final mediaUrl = report['media_url'] as String?;
    final createdAtStr = report['created_at'] as String?;
    final createdAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr)
        : null;
    final timeAgoText = createdAt != null
        ? timeago.format(createdAt, locale: 'es')
        : 'Desconocido';

    final color = _colorPorCategoria(category);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E1E3E) : Colors.white;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Título
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, color: color, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reporte en Zona $zoneNumber',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Imagen (si existe)
                if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.withValues(alpha: 0.1),
                              child: const Center(
                                child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey.withValues(alpha: 0.05),
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Badges: Categoría + Riesgo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Badge Categoría
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_categoryIconFor(category), size: 14, color: const Color(0xFF1565C0)),
                            const SizedBox(width: 6),
                            Text(
                              _categoryLabelFor(category),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1565C0)),
                            ),
                          ],
                        ),
                      ),

                      // Badge Riesgo
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: color),
                            const SizedBox(width: 6),
                            Text(
                              _labelRiesgo(riskLevel),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                            ),
                          ],
                        ),
                      ),

                      // Badge tiempo
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, size: 14, color: isDark ? Colors.white54 : Colors.black54),
                            const SizedBox(width: 6),
                            Text(
                              timeAgoText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Descripción
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),

                // Botón de acción
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        debugPrint('Confirmar reporte $zoneNumber como real');
                      },
                      icon: const Icon(Icons.shield, size: 18),
                      label: const Text(
                        'Confirmar que es real 🛡️',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.safeGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _labelRiesgo(String riskLevel) {
    switch (riskLevel) {
      case 'baja': return 'Baja';
      case 'media': return 'Media';
      case 'alta': return 'Alta';
      case 'critica': return 'Crítica';
      default: return riskLevel;
    }
  }

  String _categoryLabelFor(String category) {
    switch (category) {
      case 'robo': return 'Robo';
      case 'sospechoso': return 'Sospechoso';
      case 'extorsion': return 'Extorsión';
      case 'alumbrado': return 'Alumbrado';
      default: return 'Otros';
    }
  }

  IconData _categoryIconFor(String category) {
    switch (category) {
      case 'robo': return Icons.visibility_off;
      case 'sospechoso': return Icons.person_search;
      case 'extorsion': return Icons.block;
      case 'alumbrado': return Icons.lightbulb_outline;
      default: return Icons.info_outline;
    }
  }

  void _toggleStyle() => setState(() => _useDarkStyle = !_useDarkStyle);

  void _goToGames() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GamesHubScreen(userCode: widget.userCode, zone: 0),
      ),
    );
  }

  /// Construye un marcador de POI con ícono y color personalizados.
  Marker _buildPoiMarker({
    required double lat,
    required double lng,
    required String name,
    required String type,
    required IconData icon,
    required Color iconColor,
  }) {
    return Marker(
      point: LatLng(lat, lng),
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: () => _mostrarInfoPoi(name, type),
        child: Container(
          decoration: BoxDecoration(
            color: iconColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: iconColor.withValues(alpha: 0.4),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  /// Filtra las comisarías por proximidad al centro de Collique (radio ~2 km).
  /// Ordena por distancia y retorna las más cercanas.
  List<Marker> _filtrarComisariasCercanas() {
    // Usar el centro de Collique como referencia de ubicación
    final refLat = LocationService.colliqueLat;
    final refLng = LocationService.colliqueLng;
    const double maxRadiusMeters = 2500; // 2.5 km

    final stations = LocationService.policeStations.where((s) {
      final lat = s['lat'] as double;
      final lng = s['lng'] as double;
      final distance = LocationService.calculateDistance(refLat, refLng, lat, lng);
      return distance <= maxRadiusMeters;
    }).toList();

    // Ordenar por distancia (más cercanas primero)
    stations.sort((a, b) {
      final distA = LocationService.calculateDistance(
        refLat, refLng, a['lat'] as double, a['lng'] as double,
      );
      final distB = LocationService.calculateDistance(
        refLat, refLng, b['lat'] as double, b['lng'] as double,
      );
      return distA.compareTo(distB);
    });

    return stations.map((station) {
      final lat = station['lat'] as double;
      final lng = station['lng'] as double;
      final name = station['name'] as String;
      final type = station['type'] as String;

      IconData icon;
      Color iconColor;
      switch (type) {
        case 'comisaria':
          icon = Icons.local_police;
          iconColor = const Color(0xFF1565C0);
          break;
        case 'puesto':
          icon = Icons.security;
          iconColor = const Color(0xFF2E7D32);
          break;
        case 'serenazgo':
          icon = Icons.directions_walk;
          iconColor = const Color(0xFFE65100);
          break;
        default:
          icon = Icons.location_on;
          iconColor = Colors.blue;
      }

      return _buildPoiMarker(
        lat: lat,
        lng: lng,
        name: name,
        type: type,
        icon: icon,
        iconColor: iconColor,
      );
    }).toList();
  }

  /// Muestra un SnackBar con información del POI tocado.
  void _mostrarInfoPoi(String name, String type) {
    final typeLabel = switch (type) {
      'comisaria' => 'Comisaría',
      'puesto'    => 'Puesto Policial',
      'serenazgo' => 'Serenazgo',
      _           => 'Punto de seguridad',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.local_police, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(name, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Riesgo - Collique'),
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
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ),
          if (!_isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_reports.length} reportes',
                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // === MAPA PRINCIPAL ===
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-11.9330, -77.0450),
              initialZoom: 14.5,
              minZoom: 13.0,
              maxZoom: 17.0,
              cameraConstraint: CameraConstraint.contain(bounds: _colliqueBounds),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: _currentTileUrl,
                userAgentPackageName: 'com.safezone.app',
              ),

              // Marcadores agrupados con clustering
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 60,
                  size: const Size(40, 40),
                  markers: _construirMarcadores(),
                  polygonOptions: const PolygonOptions(
                    borderColor: Colors.transparent,
                    color: Colors.transparent,
                  ),
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryGreen, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Zonas de Collique (1-14)
              MarkerLayer(
                markers: List.generate(14, (i) {
                  final coords = LocationService.zoneCoordinates[i + 1];
                  if (coords == null) {
                    return Marker(
                      point: const LatLng(0, 0),
                      width: 0, height: 0,
                      child: const SizedBox.shrink(),
                    );
                  }
                  return Marker(
                    point: LatLng(coords['lat']!, coords['lng']!),
                    width: 50,
                    height: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Z${i + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // === PUNTOS DE INTERÉS (POIs) ===
              // Hospital, Museo, Comisarías cercanas
              MarkerLayer(
                markers: [
                  // Hospital Sergio Bernales
                  _buildPoiMarker(
                    lat: -11.9312,
                    lng: -77.0698,
                    name: 'Hospital Sergio Bernales',
                    type: 'hospital',
                    icon: Icons.local_hospital,
                    iconColor: const Color(0xFFE53935),
                  ),
                  // Museo de los Colli
                  _buildPoiMarker(
                    lat: -11.9265,
                    lng: -77.0665,
                    name: 'Museo de los Colli',
                    type: 'museo',
                    icon: Icons.museum,
                    iconColor: const Color(0xFF8D6E63),
                  ),
                  // Comisarías y puestos (filtrados por proximidad)
                  ..._filtrarComisariasCercanas(),
                ],
              ),
            ],
          ),

          // === LEYENDA DE CATEGORÍAS ===
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
                    const Text('Categorías', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    _LegendItem(color: const Color(0xFFFF0000), label: 'Robo'),
                    _LegendItem(color: const Color(0xFFFFA500), label: 'Sospechoso'),
                    _LegendItem(color: const Color(0xFFFFFF00), label: 'Alumbrado'),
                    _LegendItem(color: Colors.grey, label: 'Otros'),
                    const Divider(height: 8),
                    _LegendItem(color: AppTheme.primaryGreen, label: 'Cluster'),
                  ],
                ),
              ),
            ),
          ),

          // === LEYENDA DE ANTIGÜEDAD (evaluación dinámica) ===
          Positioned(
            left: 12,
            bottom: 210,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Antigüedad', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    _LegendItem(
                      color: const Color(0xFFFF0000),
                      label: '0–12 h (${_reports.where((r) => _colorPorAntiguedad(r['created_at'] as String?) == const Color(0xFFFF0000)).length})',
                    ),
                    _LegendItem(
                      color: const Color(0xFFFFA500),
                      label: '12h–2d (${_reports.where((r) => _colorPorAntiguedad(r['created_at'] as String?) == const Color(0xFFFFA500)).length})',
                    ),
                    _LegendItem(
                      color: const Color(0xFFFFFF00),
                      label: '2–6 d (${_reports.where((r) => _colorPorAntiguedad(r['created_at'] as String?) == const Color(0xFFFFFF00)).length})',
                    ),
                    _LegendItem(
                      color: const Color(0xFF0000FF),
                      label: '7 d+ (${_reports.where((r) => _colorPorAntiguedad(r['created_at'] as String?) == const Color(0xFF0000FF)).length})',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // === BOTÓN ESTILO MAPA ===
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
                const SizedBox(height: 4),
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

          // === BOTÓN JUEGOS ===
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

          // === CARGA INICIAL ===
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.2),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

// ================================================================
// WIDGET: PIN DEL MARCADOR CON COLOR POR CATEGORÍA
// ================================================================
class _MarkerPin extends StatelessWidget {
  final Color color;
  final String? category;

  const _MarkerPin({required this.color, this.category});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (category) {
      case 'robo':
        icon = Icons.visibility_off;
        break;
      case 'sospechoso':
        icon = Icons.person_search;
        break;
      case 'extorsion':
        icon = Icons.block;
        break;
      case 'alumbrado':
        icon = Icons.lightbulb_outline;
        break;
      default:
        icon = Icons.info_outline;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        // Pin pointer
        Container(
          width: 0,
          height: 0,
          margin: const EdgeInsets.only(top: -1),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.transparent, width: 6),
              right: BorderSide(color: Colors.transparent, width: 6),
              top: BorderSide(color: color, width: 8),
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================
// WIDGET: ITEM DE LEYENDA
// ================================================================
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
