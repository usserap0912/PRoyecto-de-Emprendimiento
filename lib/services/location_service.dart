import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:safezone/services/poi_catalog.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  /// Obtiene la posición actual del dispositivo (una vez).
  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// Obtiene un stream de posición continua (tracking en tiempo real).
  /// Retorna null si no hay permisos.
  Stream<Position>? getPositionStream() {
    try {
      return Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // actualizar cada 5 metros
          timeLimit: null, // sin límite de tiempo
        ),
      );
    } catch (e) {
      debugPrint('Error creando stream de posición: $e');
      return null;
    }
  }

  /// Detiene el stream de posición.
  void stopPositionStream() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Obtiene la dirección a partir de coordenadas
  Future<String?> getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return '${place.street ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''}';
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// La detección territorial permanece deshabilitada hasta disponer de
  /// límites oficiales verificables. Los puntos territoriales I–VI no
  /// permiten determinar si una ubicación pertenece a una zona.
  static int? detectZone(double lat, double lng) {
    return null;
  }

  /// Nombre compatible para pantallas heredadas. VII–X pueden existir sin
  /// geometría verificada; este nombre no afirma límites ni coordenadas.
  static String zoneName(int zoneNum) {
    const romanNumerals = <int, String>{
      1: 'I',
      2: 'II',
      3: 'III',
      4: 'IV',
      5: 'V',
      6: 'VI',
      7: 'VII',
      8: 'VIII',
      9: 'IX',
      10: 'X',
    };
    final numeral = romanNumerals[zoneNum];
    return numeral == null ? 'Zona no verificada' : 'Collique - Zona $numeral';
  }

  // Fallback operativo heredado usado por servicios ajenos al mapa de riesgo.
  // La cámara territorial ya no depende de esta coordenada.
  static const double colliqueLat = -11.9330;
  static const double colliqueLng = -77.0230;

  // Referencias verificadas utilizadas por flujos heredados.
  static const double hospitalLat = -11.9141196;
  static const double hospitalLng = -77.0376892;
  static const double comisariaLat = -11.9130804;
  static const double comisariaLng = -77.0161997;

  // ================================================================
  // PUNTOS DE REFERENCIA (POIs)
  // ================================================================

  static const String _legacyPoiSource = 'Datos heredados del proyecto';

  static Map<String, dynamic> _unverifiedPoi({
    required String name,
    required double lat,
    required double lng,
    required String type,
    required String verificationReason,
    String? source,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'name': name,
      'lat': lat,
      'lng': lng,
      'type': type,
      'verified': false,
      'verificationStatus': PoiCatalog.unverifiedStatus,
      'productionVisible': false,
      'source': source ?? _legacyPoiSource,
      'verificationReason': verificationReason,
      ...metadata,
    };
  }

  /// Getters compatibles derivados de una única fuente de producción.
  static List<Map<String, dynamic>> get policeStations =>
      PoiCatalog.byCategory('security');
  static List<Map<String, dynamic>> get schools =>
      PoiCatalog.byCategory('education');
  static List<Map<String, dynamic>> get parks => const [];
  static List<Map<String, dynamic>> get markets =>
      PoiCatalog.byCategory('markets');
  static List<Map<String, dynamic>> get healthCenters =>
      PoiCatalog.byCategory('health');
  static List<Map<String, dynamic>> get museums =>
      PoiCatalog.byCategory('culture');
  static List<Map<String, dynamic>> get fuelStations =>
      PoiCatalog.byCategory('fuel');
  static List<Map<String, dynamic>> get transportation => const [];
  static List<Map<String, dynamic>> get socialEquipment =>
      PoiCatalog.byCategory('social_equipment');
  static List<Map<String, dynamic>> get cemeteries =>
      PoiCatalog.byCategory('cemetery');

  /// Datos heredados preservados para trazabilidad; nunca se renderizan.
  static List<Map<String, dynamic>> get legacyUnverifiedPlaces => [
    _unverifiedPoi(
      name: 'Comisaría PNP Comas Collique',
      lat: -11.92138,
      lng: -77.02264,
      type: 'comisaria',
      verificationReason:
          'La coordenada heredada está a 1159 m del objeto OSM homónimo.',
      metadata: {
        'referenceSource': 'OpenStreetMap',
        'referenceSourceId': 'way/318952708',
        'phone': '(01) 558-2798',
        'emergency_phone': '105',
      },
    ),
    _unverifiedPoi(
      name: 'Serenazgo de Collique',
      lat: -11.9135,
      lng: -77.0275,
      type: 'serenazgo',
      verificationReason:
          'No se encontró un objeto homónimo verificable cerca del pin.',
      metadata: {'phone': '(01) 575-4321', 'emergency_phone': '116'},
    ),
    _unverifiedPoi(
      name: 'I.E. N° 2099 - Collique',
      lat: -11.9165,
      lng: -77.0325,
      type: 'colegio',
      verificationReason:
          'Los centros educativos cartografiados alrededor tienen otros nombres.',
    ),
    _unverifiedPoi(
      name: 'I.E. San Martín de Porres',
      lat: -11.9120,
      lng: -77.0275,
      type: 'colegio',
      verificationReason:
          'El objeto OSM homónimo está aproximadamente a 259 m.',
      metadata: {
        'referenceSource': 'OpenStreetMap',
        'referenceSourceId': 'way/436455874',
      },
    ),
    _unverifiedPoi(
      name: 'I.E. Santa Rosa de Collique',
      lat: -11.9095,
      lng: -77.0315,
      type: 'colegio',
      verificationReason:
          'No se encontró una coincidencia homónima verificable cerca del pin.',
    ),
    _unverifiedPoi(
      name: 'I.E. Los Olivos de Collique',
      lat: -11.9195,
      lng: -77.0300,
      type: 'colegio',
      verificationReason:
          'No se encontró una coincidencia homónima verificable cerca del pin.',
    ),
    _unverifiedPoi(
      name: 'I.E. Señor de los Milagros',
      lat: -11.9135,
      lng: -77.0200,
      type: 'colegio',
      verificationReason:
          'No se encontró una coincidencia homónima verificable cerca del pin.',
    ),
    _unverifiedPoi(
      name: 'I.E. Mariscal Cáceres',
      lat: -11.9165,
      lng: -77.0370,
      type: 'colegio',
      verificationReason:
          'Los centros educativos cartografiados alrededor tienen otros nombres.',
    ),
    _unverifiedPoi(
      name: 'Parque Túpac Amaru',
      lat: -11.9160,
      lng: -77.0365,
      type: 'parque',
      verificationReason:
          'Hay parques cercanos, pero ninguno valida este nombre y coordenada.',
    ),
    _unverifiedPoi(
      name: 'Parque Los Olivos',
      lat: -11.9190,
      lng: -77.0300,
      type: 'parque',
      verificationReason:
          'No se encontró una coincidencia homónima verificable cerca del pin.',
    ),
    _unverifiedPoi(
      name: 'Parque Collique Alto',
      lat: -11.9075,
      lng: -77.0210,
      type: 'parque',
      verificationReason:
          'No se encontró una coincidencia homónima verificable cerca del pin.',
    ),
    _unverifiedPoi(
      name: 'Losa Deportiva Collique',
      lat: -11.9110,
      lng: -77.0235,
      type: 'parque',
      verificationReason:
          'No se encontró un objeto deportivo homónimo verificable cerca del pin.',
    ),
    _unverifiedPoi(
      name: 'Mercado Santa Luzmila',
      lat: -11.9440,
      lng: -77.0655,
      type: 'mercado',
      verificationReason:
          'OSM registra otros mercados cercanos, pero no valida este nombre y pin.',
    ),
    _unverifiedPoi(
      name: 'Centro de Salud Santa Luzmila',
      lat: -11.9445,
      lng: -77.0655,
      type: 'postas',
      verificationReason:
          'El nombre es ambiguo y Santa Luzmila I está aproximadamente a 338 m.',
      metadata: {
        'referenceSource': 'OpenStreetMap',
        'referenceSourceId': 'way/435722152',
        'phone': '(01) 536-1800',
      },
    ),
  ];

  static List<Map<String, dynamic>> get auditedPlaces =>
      List<Map<String, dynamic>>.unmodifiable(<Map<String, dynamic>>[
        ...PoiCatalog.auditedPlaces,
        ...legacyUnverifiedPlaces,
      ]);

  static List<Map<String, dynamic>> get partiallyVerifiedPlaces =>
      PoiCatalog.auditedByStatus(PoiCatalog.partiallyVerifiedStatus);

  static List<Map<String, dynamic>> get unverifiedPlaces =>
      List<Map<String, dynamic>>.unmodifiable(<Map<String, dynamic>>[
        ...PoiCatalog.auditedByStatus(PoiCatalog.unverifiedStatus),
        ...legacyUnverifiedPlaces,
      ]);

  static List<Map<String, dynamic>> get rejectedPlaces =>
      PoiCatalog.auditedByStatus(PoiCatalog.rejectedStatus);

  static bool isProductionPoi(Map<String, dynamic> poi) =>
      PoiCatalog.isProductionPoi(poi);

  /// Única colección permitida para búsqueda y renderizado en producción.
  static List<Map<String, dynamic>> get allPois => PoiCatalog.productionPois;

  /// Encuentra la estación policial más cercana a una ubicación.
  /// Retorna el mapa de la estación más cercana con distancia incluida.
  static Map<String, dynamic> findNearestStation(double lat, double lng) {
    Map<String, dynamic>? nearest;
    double minDistance = double.infinity;

    for (final station in policeStations) {
      final sLat = station['lat'] as double;
      final sLng = station['lng'] as double;
      final distance = calculateDistance(lat, lng, sLat, sLng);

      if (distance < minDistance) {
        minDistance = distance;
        nearest = Map<String, dynamic>.from(station);
        nearest['distance_meters'] = distance;
      }
    }

    return nearest ?? policeStations.first;
  }

  /// Encuentra el POI más cercano de cualquier tipo a una ubicación.
  static Map<String, dynamic>? findNearestPoi(
    double lat,
    double lng, {
    String? type,
  }) {
    final pois = type != null
        ? allPois.where((p) => p['type'] == type).toList()
        : allPois;

    Map<String, dynamic>? nearest;
    double minDistance = double.infinity;

    for (final poi in pois) {
      final pLat = poi['lat'] as double;
      final pLng = poi['lng'] as double;
      final distance = calculateDistance(lat, lng, pLat, pLng);

      if (distance < minDistance) {
        minDistance = distance;
        nearest = Map<String, dynamic>.from(poi);
        nearest['distance_meters'] = distance;
      }
    }

    return nearest;
  }

  /// Colores de interfaz para las zonas reconocidas I–X. No representan áreas.
  static List<Color> get zoneColors => [
    const Color(0xFF1565C0), // Z1 - Azul intenso
    const Color(0xFF1E88E5), // Z2 - Azul
    const Color(0xFF42A5F5), // Z3 - Azul claro
    const Color(0xFF26A69A), // Z4 - Teal
    const Color(0xFF66BB6A), // Z5 - Verde
    const Color(0xFF9CCC65), // Z6 - Verde lima
    const Color(0xFFFFEE58), // Z7 - Amarillo
    const Color(0xFFFFCA28), // Z8 - Ámbar
    const Color(0xFFBDBDBD), // Z9 - Sin geometría
    const Color(0xFF9E9E9E), // Z10 - Referencia histórica sin geometría
  ];

  // ============================================================
  // CÁLCULO DE DISTANCIA (Fórmula de Haversine)
  // ============================================================

  /// Calcula la distancia en metros entre dos puntos geográficos.
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // metros

    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (3.141592653589793 / 180);
  }

  /// Formatea una distancia en metros: "X m" o "X.X km".
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }
}
