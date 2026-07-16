import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:safezone/theme/app_theme.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/services/sound_service.dart';
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
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  // Reportes en tiempo real vía stream de Supabase
  List<Map<String, dynamic>> _reports = [];
  StreamSubscription<List<Map<String, dynamic>>>? _reportsSubscription;
  bool _isLoading = true;
  bool _streamError = false;

  // Ubicación del usuario
  double? _userLat;
  double? _userLng;
  bool _isLocatingUser = false;
  int? _currentZone; // Zona actual detectada
  StreamSubscription<Position>? _positionSubscription;

  // Check-in de zona segura
  bool _isCheckingIn = false;
  bool _hasAutoCentered = false;

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

  // Colores distintivos para cada zona (gradiente de azul a rojo)
  static final List<Color> _zoneColors = [
    const Color(0xFF1565C0), // Z1 - Azul intenso
    const Color(0xFF1E88E5), // Z2 - Azul
    const Color(0xFF42A5F5), // Z3 - Azul claro
    const Color(0xFF26A69A), // Z4 - Teal
    const Color(0xFF66BB6A), // Z5 - Verde
    const Color(0xFF9CCC65), // Z6 - Verde lima
    const Color(0xFFFFEE58), // Z7 - Amarillo
    const Color(0xFFFFCA28), // Z8 - Ámbar
    const Color(0xFFFFA726), // Z9 - Naranja
    const Color(0xFFEF6C00), // Z10 - Naranja intenso
    const Color(0xFFE65100), // Z11 - Naranja oscuro
    const Color(0xFFBF360C), // Z12 - Rojo ladrillo
    const Color(0xFFD32F2F), // Z13 - Rojo
    const Color(0xFFB71C1C), // Z14 - Rojo oscuro
  ];

  // ================================================================
  // INICIALIZACIÓN
  // ================================================================
  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('es', timeago.EsMessages());
    _initReportsStream();
    _loadUserLocation();
  }

  @override
  void dispose() {
    _reportsSubscription?.cancel();
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Obtiene la ubicación actual del usuario y inicia tracking continuo.
  Future<void> _loadUserLocation() async {
    setState(() => _isLocatingUser = true);
    try {
      final position = await _locationService.getCurrentLocation();
      if (mounted && position != null) {
        _updatePosition(position.latitude, position.longitude);

        // Auto-centrar en la ubicación del usuario al cargar (solo la primera vez)
        if (!_hasAutoCentered && mounted) {
          _hasAutoCentered = true;
          _mapController.move(LatLng(position.latitude, position.longitude), 15.5);
          
          // Mostrar snackbar de bienvenida con ubicación
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.my_location, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Ubicación detectada. Mapa centrado en tu posición.'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2196F3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            ),
          );
        }

        // Iniciar tracking continuo
        _startContinuousTracking();
      }
    } catch (e) {
      debugPrint('Error obteniendo ubicacion del usuario: $e');
    } finally {
      if (mounted) setState(() => _isLocatingUser = false);
    }
  }

  /// Inicia el stream de posición continua (se actualiza cada 5 metros).
  void _startContinuousTracking() {
    _positionSubscription?.cancel();
    final stream = _locationService.getPositionStream();
    if (stream == null) return;

    _positionSubscription = stream.listen((Position pos) {
      if (mounted) {
        _updatePosition(pos.latitude, pos.longitude);
      }
    }, onError: (Object error) {
      debugPrint('Error en tracking continuo: $error');
    });
  }

  /// Actualiza la posición del usuario y detecta la zona actual.
  void _updatePosition(double lat, double lng) {
    final zone = LocationService.detectZone(lat, lng);
    setState(() {
      _userLat = lat;
      _userLng = lng;
      _currentZone = zone;
    });
  }

  /// Centra el mapa en la ubicación del usuario o en Collique.
  Future<void> _recenterMap() async {
    if (_userLat != null && _userLng != null) {
      _mapController.move(LatLng(_userLat!, _userLng!), 15.5);
    } else {
      // Si no tenemos ubicación, intentamos obtenerla
      await _loadUserLocation();
      if (_userLat != null && _userLng != null && mounted) {
        _mapController.move(LatLng(_userLat!, _userLng!), 15.5);
      } else {
        // Fallback: centro de Collique
        _mapController.move(
          const LatLng(-11.9330, -77.0450),
          14.5,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Centrado en Collique. Activa el GPS para ver tu ubicación.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  // ================================================================
  // SUPABASE: STREAM EN VIVO DE REPORTES
  // ================================================================
  void _initReportsStream() {
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      _reportsSubscription = _supabase.client
          .from('reports')
          .stream(primaryKey: ['id'])
          .gte('created_at', sevenDaysAgo)
          .order('created_at', ascending: false)
          .listen(
        (List<Map<String, dynamic>> data) {
          if (mounted) {
            setState(() {
              _reports = data;
              _isLoading = false;
              _streamError = false;
            });
          }
        },
        onError: (Object error) {
          debugPrint('Error en stream de reportes: $error');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _streamError = true;
            });
          }
        },
      );

      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && _isLoading) {
          setState(() {
            _isLoading = false;
            _streamError = true;
          });
        }
      });
    } catch (e) {
      debugPrint('Error iniciando stream de reportes: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _streamError = true;
        });
      }
    }
  }

  // ================================================================
  // COLORES POR CATEGORÍA Y ANTIGÜEDAD
  // ================================================================
  Color _colorPorCategoria(String? category) {
    switch (category) {
      case 'robo':
        return const Color(0xFFFF0000);
      case 'sos':
        return AppTheme.sosRed;
      case 'sospechoso':
        return const Color(0xFFFFA500);
      case 'extorsion':
        return const Color(0xFFFFA500);
      case 'alumbrado':
        return const Color(0xFFFFFF00);
      default:
        return Colors.grey;
    }
  }

  Color _colorPorAntiguedad(String? createdAtStr) {
    final createdAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr)
        : null;
    if (createdAt == null) return Colors.grey;

    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inHours <= 12) {
      return const Color(0xFFFF0000);
    }
    if (difference.inDays >= 2 && difference.inDays <= 6) {
      return const Color(0xFFFFFF00);
    }
    if (difference.inDays >= 7) {
      return const Color(0xFF0000FF);
    }
    return const Color(0xFFFFA500);
  }

  // ================================================================
  // MARCADORES DE REPORTES
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
  // BOTTOM SHEET DE DETALLE DEL REPORTE (con "Cómo llegar")
  // ================================================================
  void _mostrarBottomSheet(Map<String, dynamic> report) {
    final reportLat = (report['lat'] ?? report['latitude']) as num?;
    final reportLng = (report['lng'] ?? report['longitude']) as num?;
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

    // Distancia desde el usuario al reporte
    String distanciaTexto = '';
    if (_userLat != null && _userLng != null && reportLat != null && reportLng != null) {
      final dist = LocationService.calculateDistance(
        _userLat!, _userLng!, reportLat.toDouble(), reportLng.toDouble(),
      );
      distanciaTexto = LocationService.formatDistance(dist);
    }

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
            maxHeight: MediaQuery.of(context).size.height * 0.75,
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

                const SizedBox(height: 12),

                // Distancia desde el usuario
                if (distanciaTexto.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(Icons.near_me, size: 14, color: isDark ? Colors.white54 : Colors.black54),
                        const SizedBox(width: 6),
                        Text(
                          'A $distanciaTexto de ti',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

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

                // Badges: Categoría + Riesgo + Tiempo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
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

                const SizedBox(height: 20),

                // Botones de acción
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    children: [
                      // Botón "Cómo llegar" - abre Google Maps
                      if (reportLat != null && reportLng != null)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => _abrirGoogleMaps(
                              reportLat.toDouble(),
                              reportLng.toDouble(),
                            ),
                            icon: const Icon(Icons.directions, size: 18),
                            label: const Text(
                              'Cómo llegar',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2196F3),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      if (reportLat != null && reportLng != null)
                        const SizedBox(height: 10),
                      // Botón confirmar
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(Icons.shield, color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Text('Gracias por confirmar. Seguimos vigilando 🛡️'),
                                  ],
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.shield, size: 18),
                          label: const Text(
                            'Confirmar que es real',
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
                    ],
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
      case 'critica': return 'Critica';
      default: return riskLevel;
    }
  }

  String _categoryLabelFor(String category) {
    switch (category) {
      case 'robo': return 'Robo';
      case 'sos': return 'S.O.S.';
      case 'sospechoso': return 'Sospechoso';
      case 'extorsion': return 'Extorsion';
      case 'alumbrado': return 'Alumbrado';
      default: return 'Otros';
    }
  }

  IconData _categoryIconFor(String category) {
    switch (category) {
      case 'robo': return Icons.visibility_off;
      case 'sos': return Icons.sos;
      case 'sospechoso': return Icons.person_search;
      case 'extorsion': return Icons.block;
      case 'alumbrado': return Icons.lightbulb_outline;
      default: return Icons.info_outline;
    }
  }

  /// Abre Google Maps con la ruta hacia las coordenadas indicadas.
  Future<void> _abrirGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir Google Maps.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Realiza un check-in de zona segura (+3 puntos vecinales).
  Future<void> _doSafeCheckin() async {
    if (_isCheckingIn) return;
    setState(() => _isCheckingIn = true);

    try {
      final result = await _supabase.doSafeCheckin(
        userCode: widget.userCode,
        zone: _currentZone ?? 0,
        lat: _userLat,
        lng: _userLng,
      );

      final success = result['success'] as bool? ?? false;
      final message = result['message'] as String? ?? 'Zona segura registrada';

      if (mounted) {
        setState(() {
          _isCheckingIn = false;
        });

        SoundService().play('report_sent');
        HapticFeedback.lightImpact();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.info_outline,
                  color: success ? Colors.greenAccent : Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        success ? 'Zona segura registrada' : 'Check-in en pausa',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        message,
                        style: const TextStyle(fontSize: 12),
                      ),
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

        if (success && mounted) {
          final totalPoints = result['total_points'] as int? ?? 0;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.emoji_events, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Text('+3 puntos vecinales! Total: $totalPoints pts'),
                    ],
                  ),
                  backgroundColor: AppTheme.primaryGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('RiskMapScreen: Error en safe checkin: $e');
      if (mounted) {
        setState(() => _isCheckingIn = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al registrar zona segura'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _toggleStyle() => setState(() => _useDarkStyle = !_useDarkStyle);

  /// Construye un marcador de POI con icono y color personalizados.
  Marker _buildPoiMarker({
    required double lat,
    required double lng,
    required Map<String, dynamic> poiData,
  }) {
    final type = poiData['type'] as String;

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
      case 'colegio':
        icon = Icons.school;
        iconColor = const Color(0xFF9C27B0);
        break;
      case 'parque':
        icon = Icons.park;
        iconColor = const Color(0xFF4CAF50);
        break;
      case 'mercado':
        icon = Icons.store;
        iconColor = const Color(0xFF795548);
        break;
      case 'hospital':
        icon = Icons.local_hospital;
        iconColor = const Color(0xFFE53935);
        break;
      case 'postas':
        icon = Icons.medical_services;
        iconColor = const Color(0xFFF44336);
        break;
      case 'museo':
        icon = Icons.museum;
        iconColor = const Color(0xFF8D6E63);
        break;
      default:
        icon = Icons.location_on;
        iconColor = Colors.blue;
    }

    return Marker(
      point: LatLng(lat, lng),
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: () => _mostrarInfoPoi(poiData),
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

  /// Filtra las comisarias por proximidad al centro de Collique.
  List<Marker> _filtrarComisariasCercanas() {
    final refLat = LocationService.colliqueLat;
    final refLng = LocationService.colliqueLng;
    const double maxRadiusMeters = 2500;

    final stations = LocationService.policeStations.where((s) {
      final lat = s['lat'] as double;
      final lng = s['lng'] as double;
      final distance = LocationService.calculateDistance(refLat, refLng, lat, lng);
      return distance <= maxRadiusMeters;
    }).toList();

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
      return _buildPoiMarker(
        lat: station['lat'] as double,
        lng: station['lng'] as double,
        poiData: station,
      );
    }).toList();
  }

  /// Construye marcadores para colegios cercanos.
  List<Marker> _construirMarcadoresColegios() {
    return LocationService.schools.map((school) {
      return _buildPoiMarker(
        lat: school['lat'] as double,
        lng: school['lng'] as double,
        poiData: school,
      );
    }).toList();
  }

  /// Construye marcadores para parques cercanos.
  List<Marker> _construirMarcadoresParques() {
    return LocationService.parks.map((park) {
      return _buildPoiMarker(
        lat: park['lat'] as double,
        lng: park['lng'] as double,
        poiData: park,
      );
    }).toList();
  }

  /// Construye marcadores para mercados cercanos.
  List<Marker> _construirMarcadoresMercados() {
    return LocationService.markets.map((market) {
      return _buildPoiMarker(
        lat: market['lat'] as double,
        lng: market['lng'] as double,
        poiData: market,
      );
    }).toList();
  }

  /// Construye marcadores para centros de salud cercanos.
  List<Marker> _construirMarcadoresSalud() {
    return LocationService.healthCenters.map((hc) {
      return _buildPoiMarker(
        lat: hc['lat'] as double,
        lng: hc['lng'] as double,
        poiData: hc,
      );
    }).toList();
  }

  /// Muestra un Bottom Sheet con informacion completa del POI tocado.
  void _mostrarInfoPoi(Map<String, dynamic> poiData) {
    final name = poiData['name'] as String;
    final type = poiData['type'] as String;
    final phone = poiData['phone'] as String?;
    final emergencyPhone = poiData['emergency_phone'] as String?;
    final poiLat = poiData['lat'] as double;
    final poiLng = poiData['lng'] as double;

    // Distancia desde el usuario
    String distText = '';
    if (_userLat != null && _userLng != null) {
      final dist = LocationService.calculateDistance(
        _userLat!, _userLng!, poiLat, poiLng,
      );
      distText = LocationService.formatDistance(dist);
    }

    final typeLabel = switch (type) {
      'comisaria' => 'Comisaria',
      'puesto'    => 'Puesto Policial',
      'serenazgo' => 'Serenazgo',
      'colegio'   => 'Colegio',
      'parque'    => 'Parque',
      'mercado'   => 'Mercado',
      'hospital'  => 'Hospital',
      'postas'    => 'Centro de Salud',
      'museo'     => 'Museo',
      _           => 'Punto de interes',
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E1E3E) : Colors.white;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Icono grande del tipo
                Container(
                  width: 56, height: 56,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    _iconForType(type),
                    size: 28,
                    color: _colorForType(type),
                  ),
                ),

                // Nombre
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // Tipo + distancia
                Text(
                  '$typeLabel${distText.isNotEmpty ? ' - $distText' : ''}',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),

                const SizedBox(height: 20),

                // Teléfonos
                if (phone != null || emergencyPhone != null) ...[
                  if (phone != null)
                    _buildInfoRow(
                      icon: Icons.phone,
                      label: phone,
                      onTap: () => _llamar(phone),
                      isDark: isDark,
                    ),
                  if (emergencyPhone != null)
                    _buildInfoRow(
                      icon: Icons.emergency,
                      label: 'Emergencia: $emergencyPhone',
                      isDark: isDark,
                      isEmergency: true,
                    ),
                  const SizedBox(height: 16),
                ],

                // Botón cómo llegar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _abrirGoogleMaps(poiLat, poiLng),
                      icon: const Icon(Icons.directions, size: 18),
                      label: const Text(
                        'Cómo llegar',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Intenta llamar a un numero telefonico.
  Future<void> _llamar(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo llamar a $phone'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    required bool isDark,
    bool isEmergency = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isEmergency
                ? Colors.red.withValues(alpha: 0.08)
                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
            border: isEmergency
                ? Border.all(color: Colors.red.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isEmergency
                    ? Colors.red
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isEmergency
                        ? Colors.red.shade700
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isEmergency ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'comisaria': return Icons.local_police;
      case 'puesto': return Icons.security;
      case 'serenazgo': return Icons.directions_walk;
      case 'colegio': return Icons.school;
      case 'parque': return Icons.park;
      case 'mercado': return Icons.store;
      case 'hospital': return Icons.local_hospital;
      case 'postas': return Icons.medical_services;
      case 'museo': return Icons.museum;
      default: return Icons.location_on;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'comisaria': return const Color(0xFF1565C0);
      case 'puesto': return const Color(0xFF2E7D32);
      case 'serenazgo': return const Color(0xFFE65100);
      case 'colegio': return const Color(0xFF9C27B0);
      case 'parque': return const Color(0xFF4CAF50);
      case 'mercado': return const Color(0xFF795548);
      case 'hospital': return const Color(0xFFE53935);
      case 'postas': return const Color(0xFFF44336);
      case 'museo': return const Color(0xFF8D6E63);
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Mapa de Riesgo'),
            if (_currentZone != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Z${_currentZone!}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.sectionMapa, Color(0xFF1B5E20)],
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

              // Zonas de Collique (1-14) - etiquetas
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

              // === MARCADOR DE UBICACION DEL USUARIO ===
              if (_userLat != null && _userLng != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_userLat!, _userLng!),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () {
                          final zoneText = _currentZone != null
                              ? 'Estas en Zona $_currentZone (${LocationService.zoneName(_currentZone!)})'
                              : 'Estas aqui';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.person_pin, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(zoneText)),
                                ],
                              ),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2196F3).withValues(alpha: 0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ],
                ),

              // === POLIGONOS DE ZONAS ===
              PolygonLayer(
                polygons: List.generate(14, (i) {
                  final zoneNum = i + 1;
                  final vertices = LocationService.zonePolygons[zoneNum];
                  if (vertices == null || vertices.length < 3) return null;

                  final color = _zoneColors[i];

                  return Polygon(
                    points: vertices.map((v) => LatLng(v['lat']!, v['lng']!)).toList(),
                    color: color.withValues(alpha: 0.08),
                    borderColor: color.withValues(alpha: 0.35),
                    borderStrokeWidth: 1.5,
                  );
                }).whereType<Polygon>().toList(),
              ),

              // === PUNTOS DE INTERES (POIs) - NUEVOS ===
              // Colegios
              MarkerLayer(markers: _construirMarcadoresColegios()),
              // Parques
              MarkerLayer(markers: _construirMarcadoresParques()),
              // Mercados
              MarkerLayer(markers: _construirMarcadoresMercados()),
              // Centros de salud
              MarkerLayer(markers: _construirMarcadoresSalud()),
              // Comisarias y puestos
              MarkerLayer(markers: _filtrarComisariasCercanas()),
              // Hospital y Museo (individuales)
              MarkerLayer(
                markers: [
                  _buildPoiMarker(
                    lat: -11.9312, lng: -77.0698,
                    poiData: {'name': 'Hospital Sergio Bernales', 'type': 'hospital', 'phone': '(01) 558-0101'},
                  ),
                  _buildPoiMarker(
                    lat: -11.9265, lng: -77.0665,
                    poiData: {'name': 'Museo de los Colli', 'type': 'museo'},
                  ),
                ],
              ),
            ],
          ),

          // === LEYENDA DE CATEGORIAS ===
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
                    _LegendItem(color: AppTheme.sosRed, label: 'S.O.S.'),
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

          // === LEYENDA DE ANTIGÜEDAD ===
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
                      label: '0-12 h (${_reports.where((r) => _colorPorAntiguedad(r['created_at'] as String?) == const Color(0xFFFF0000)).length})',
                    ),
                    _LegendItem(
                      color: const Color(0xFFFFA500),
                      label: '12h-2d (${_reports.where((r) => _colorPorAntiguedad(r['created_at'] as String?) == const Color(0xFFFFA500)).length})',
                    ),
                    _LegendItem(
                      color: const Color(0xFFFFFF00),
                      label: '2-6 d (${_reports.where((r) => _colorPorAntiguedad(r['created_at'] as String?) == const Color(0xFFFFFF00)).length})',
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

          // === BOTON ESTILO MAPA ===
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

          // === BOTON ZONA SEGURA ===
          Positioned(
            left: 16,
            bottom: 365,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'safe_checkin',
                  onPressed: _isCheckingIn ? null : _doSafeCheckin,
                  backgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.85),
                  child: _isCheckingIn
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Zona segura',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          // === BOTON MI UBICACION ===
          Positioned(
            right: 16,
            bottom: 120,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  onPressed: _isLocatingUser ? null : _recenterMap,
                  backgroundColor: (_userLat != null
                          ? const Color(0xFF2196F3)
                          : (isDark ? Colors.white : Colors.black))
                      .withValues(alpha: 0.75),
                  child: _isLocatingUser
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          _userLat != null ? Icons.my_location : Icons.location_searching,
                          color: isDark ? Colors.black87 : Colors.white,
                          size: 20,
                        ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _userLat != null ? 'Mi ubicacion' : 'Centrar',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isDark ? Colors.black87 : Colors.white),
                  ),
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

          // === BANNER DE ERROR ===
          if (_streamError && _reports.isEmpty)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Colors.orange.shade50,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, size: 18, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sin conexión. Los reportes aparecerán cuando haya conexión.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade800, height: 1.3),
                        ),
                      ),
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

// ================================================================
// WIDGET: PIN DEL MARCADOR
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
      case 'sos':
        icon = Icons.sos;
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
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
