import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  // Reportes en tiempo real
  List<Map<String, dynamic>> _reports = [];
  RealtimeChannel? _realtimeChannel;
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
    _cargarReportes();
    _suscribirRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _mapController.dispose();
    super.dispose();
  }

  // ================================================================
  // SUPABASE: CARGAR REPORTES + REALTIME
  // ================================================================
  Future<void> _cargarReportes() async {
    try {
      final data = await _supabase.client
          .from('reports')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          _reports = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando reportes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _suscribirRealtime() {
    try {
      // Escuchar INSERT en la tabla 'reports' usando Realtime
      _realtimeChannel = _supabase.client
          .channel('reports-realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'reports',
            callback: (payload) {
              if (!mounted) return;
              final newRecord = Map<String, dynamic>.from(payload.newRecord);
              setState(() {
                _reports.insert(0, newRecord);
                if (_reports.length > 100) _reports.removeLast();
              });
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Error suscribiendo a Realtime: $e');
    }
  }

  // ================================================================
  // COLOR SEGÚN RISK LEVEL
  // ================================================================
  Color _colorPorRiskLevel(String? riskLevel) {
    switch (riskLevel) {
      case 'baja':
        return AppTheme.safeGreen;
      case 'media':
        return AppTheme.warningYellow;
      case 'alta':
        return AppTheme.alertOrange;
      case 'critica':
        return AppTheme.dangerRed;
      default:
        return Colors.grey;
    }
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

      final riskLevel = report['risk_level'] as String?;
      final color = _colorPorRiskLevel(riskLevel);

      return Marker(
        point: LatLng(lat.toDouble(), lng.toDouble()),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _mostrarBottomSheet(report),
          child: _MarkerPin(color: color, riskLevel: riskLevel),
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

    final color = _colorPorRiskLevel(riskLevel);
    // Usar import de Report model cuando se necesiten helpers de categoría

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
                    _LegendItem(color: AppTheme.safeGreen, label: 'Baja'),
                    _LegendItem(color: AppTheme.warningYellow, label: 'Media'),
                    _LegendItem(color: AppTheme.alertOrange, label: 'Alta'),
                    _LegendItem(color: AppTheme.dangerRed, label: 'Crítica'),
                    const Divider(height: 12),
                    _LegendItem(color: AppTheme.primaryGreen, label: 'Cluster'),
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
// WIDGET: PIN DEL MARCADOR CON COLOR
// ================================================================
class _MarkerPin extends StatelessWidget {
  final Color color;
  final String? riskLevel;

  const _MarkerPin({required this.color, this.riskLevel});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (riskLevel) {
      case 'critica': icon = Icons.warning; break;
      case 'alta': icon = Icons.warning_amber_rounded; break;
      case 'media': icon = Icons.info; break;
      default: icon = Icons.check_circle;
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
