import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

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

  /// Determina en qué zona (1-14) se encuentra un punto geográfico.
  /// Usa el algoritmo de punto-en-polígono (ray casting).
  /// Retorna null si está fuera de todas las zonas.
  static int? detectZone(double lat, double lng) {
    for (int z = 1; z <= 14; z++) {
      final vertices = zonePolygons[z];
      if (vertices == null || vertices.length < 3) continue;

      // Ray casting algorithm
      bool inside = false;
      int j = vertices.length - 1;
      for (int i = 0; i < vertices.length; i++) {
        final vi = vertices[i];
        final vj = vertices[j];
        final viLat = vi['lat']!;
        final viLng = vi['lng']!;
        final vjLat = vj['lat']!;
        final vjLng = vj['lng']!;

        if ((viLng > lng) != (vjLng > lng) &&
            lat < (vjLat - viLat) * (lng - viLng) / (vjLng - viLng) + viLat) {
          inside = !inside;
        }
        j = i;
      }
      if (inside) return z;
    }
    return null;
  }

  /// Retorna el nombre descriptivo de una zona.
  static String zoneName(int zoneNum) {
    const names = {
      1: 'Entrada - Av. Revolución',
      2: 'Mercado San Jhonny',
      3: 'Hospital Bernales',
      4: 'Comisaría PNP Collique',
      5: 'Quebrada Alta',
      6: 'Cumbre Urbana',
      7: 'Asentamientos Humanos',
      8: 'Sector 8',
      9: 'Sector 9',
      10: 'Sector 10',
      11: 'Sector 11',
      12: 'Sector 12',
      13: 'Sector 13',
      14: 'Zona más alta',
    };
    return names[zoneNum] ?? 'Zona $zoneNum';
  }

  // Coordenadas REALES de Collique (Comas, Lima) proporcionadas por la
  // comunidad. Las zonas 1-7 se organizan de forma secuencial subiendo por
  // el eje vial de la Av. Revolución, desde el Paradero Collique
  // (cruce con Av. Túpac Amaru, -11.93284, -77.04221) hasta la zona alta
  // (Calle Julio César Tello, -11.93521, -77.01254).
  static const double colliqueLat = -11.9330;
  static const double colliqueLng = -77.0230;

  /// Coordenadas de las 14 zonas de Collique (centros aproximados).
  /// Zona 1 = entrada (Paradero Collique); las zonas suben por la
  /// Av. Revolución hacia el este; 8-14 continúan hacia la zona alta.
  static Map<int, Map<String, double>> get zoneCoordinates => {
    1: {'lat': -11.9323, 'lng': -77.0401},  // Entrada - Av. Revolución (Paradero Collique)
    2: {'lat': -11.9304, 'lng': -77.0345},  // Mercado San Jhonny (eje comercial)
    3: {'lat': -11.9320, 'lng': -77.0270},  // Hospital Bernales (sector salud)
    4: {'lat': -11.9338, 'lng': -77.0210},  // Comisaría PNP Collique (seguridad)
    5: {'lat': -11.9348, 'lng': -77.0165},  // Quebrada Alta
    6: {'lat': -11.9352, 'lng': -77.0125},  // Cumbre Urbana (Calle Julio César Tello)
    7: {'lat': -11.9315, 'lng': -77.0068},  // Asentamientos Humanos (faldas del cerro)
    8: {'lat': -11.9310, 'lng': -77.0040},  // Sector 8 (zona alta)
    9: {'lat': -11.9290, 'lng': -77.0010},  // Sector 9 (zona alta)
    10: {'lat': -11.9270, 'lng': -76.9985}, // Sector 10 (zona alta)
    11: {'lat': -11.9250, 'lng': -76.9960}, // Sector 11 (zona alta)
    12: {'lat': -11.9230, 'lng': -76.9935}, // Sector 12 (zona alta)
    13: {'lat': -11.9210, 'lng': -76.9910}, // Sector 13 (zona alta)
    14: {'lat': -11.9190, 'lng': -76.9885}, // Zona más alta
  };

  // Coordenadas de puntos de referencia reales en Collique
  static const double hospitalLat = -11.91390;
  static const double hospitalLng = -77.03928;
  static const double comisariaLat = -11.92138;
  static const double comisariaLng = -77.02264;
  static const double museoLat = -11.93122;
  static const double museoLng = -77.02895;

  // ================================================================
  // POLÍGONOS DE ZONAS
  // ================================================================
  /// Polígonos aproximados de las 14 zonas de Collique (vértices en sentido horario).
  /// Las zonas 1-7 son bandas que suben por el eje de la Av. Revolución
  /// (oeste → este); las zonas 8-14 continúan hacia la zona alta.
  static Map<int, List<Map<String, double>>> get zonePolygons => {
    1: [
      {'lat': -11.9290, 'lng': -77.0435},
      {'lat': -11.9290, 'lng': -77.0373},
      {'lat': -11.9370, 'lng': -77.0373},
      {'lat': -11.9370, 'lng': -77.0435},
    ],
    2: [
      {'lat': -11.9290, 'lng': -77.0373},
      {'lat': -11.9290, 'lng': -77.0308},
      {'lat': -11.9370, 'lng': -77.0308},
      {'lat': -11.9370, 'lng': -77.0373},
    ],
    3: [
      {'lat': -11.9290, 'lng': -77.0308},
      {'lat': -11.9290, 'lng': -77.0240},
      {'lat': -11.9370, 'lng': -77.0240},
      {'lat': -11.9370, 'lng': -77.0308},
    ],
    4: [
      {'lat': -11.9290, 'lng': -77.0240},
      {'lat': -11.9290, 'lng': -77.0188},
      {'lat': -11.9370, 'lng': -77.0188},
      {'lat': -11.9370, 'lng': -77.0240},
    ],
    5: [
      {'lat': -11.9290, 'lng': -77.0188},
      {'lat': -11.9290, 'lng': -77.0145},
      {'lat': -11.9370, 'lng': -77.0145},
      {'lat': -11.9370, 'lng': -77.0188},
    ],
    6: [
      {'lat': -11.9290, 'lng': -77.0145},
      {'lat': -11.9290, 'lng': -77.0097},
      {'lat': -11.9370, 'lng': -77.0097},
      {'lat': -11.9370, 'lng': -77.0145},
    ],
    7: [
      {'lat': -11.9290, 'lng': -77.0097},
      {'lat': -11.9290, 'lng': -77.0054},
      {'lat': -11.9370, 'lng': -77.0054},
      {'lat': -11.9370, 'lng': -77.0097},
    ],
    8: [
      {'lat': -11.9290, 'lng': -77.0054},
      {'lat': -11.9290, 'lng': -77.0025},
      {'lat': -11.9370, 'lng': -77.0025},
      {'lat': -11.9370, 'lng': -77.0054},
    ],
    9: [
      {'lat': -11.9270, 'lng': -77.0025},
      {'lat': -11.9270, 'lng': -76.9998},
      {'lat': -11.9350, 'lng': -76.9998},
      {'lat': -11.9350, 'lng': -77.0025},
    ],
    10: [
      {'lat': -11.9250, 'lng': -76.9998},
      {'lat': -11.9250, 'lng': -76.9973},
      {'lat': -11.9330, 'lng': -76.9973},
      {'lat': -11.9330, 'lng': -76.9998},
    ],
    11: [
      {'lat': -11.9230, 'lng': -76.9973},
      {'lat': -11.9230, 'lng': -76.9948},
      {'lat': -11.9310, 'lng': -76.9948},
      {'lat': -11.9310, 'lng': -76.9973},
    ],
    12: [
      {'lat': -11.9210, 'lng': -76.9948},
      {'lat': -11.9210, 'lng': -76.9923},
      {'lat': -11.9290, 'lng': -76.9923},
      {'lat': -11.9290, 'lng': -76.9948},
    ],
    13: [
      {'lat': -11.9190, 'lng': -76.9923},
      {'lat': -11.9190, 'lng': -76.9898},
      {'lat': -11.9270, 'lng': -76.9898},
      {'lat': -11.9270, 'lng': -76.9923},
    ],
    14: [
      {'lat': -11.9170, 'lng': -76.9898},
      {'lat': -11.9170, 'lng': -76.9870},
      {'lat': -11.9250, 'lng': -76.9870},
      {'lat': -11.9250, 'lng': -76.9898},
    ],
  };

  // ================================================================
  // PUNTOS DE REFERENCIA (POIs)
  // ================================================================

  /// Comisarías y puntos policiales reales de Collique y alrededores (OSM).
  static List<Map<String, dynamic>> get policeStations => [
    {
      'name': 'Comisaría PNP Comas Collique',
      'lat': -11.92138,
      'lng': -77.02264,
      'type': 'comisaria',
      'phone': '(01) 558-2798',
      'emergency_phone': '105',
    },
    {
      'name': 'Comisaría PNP de la Familia - Collique',
      'lat': -11.91298,
      'lng': -77.01038,
      'type': 'comisaria',
      'phone': '(01) 558-2799',
      'emergency_phone': '105',
    },
    {
      'name': 'C.I.E. PNP Collique',
      'lat': -11.9144,
      'lng': -77.0290,
      'type': 'puesto',
      'phone': '(01) 558-2901',
      'emergency_phone': '105',
    },
    {
      'name': 'Serenazgo de Collique',
      'lat': -11.9135,
      'lng': -77.0275,
      'type': 'serenazgo',
      'phone': '(01) 575-4321',
      'emergency_phone': '116',
    },
    {
      'name': 'Comisaría PNP La Pascana',
      'lat': -11.9350,
      'lng': -77.0458,
      'type': 'comisaria',
      'phone': '(01) 562-3456',
      'emergency_phone': '105',
    },
    {
      'name': 'Comisaría PNP Santa Luzmila',
      'lat': -11.9443,
      'lng': -77.0663,
      'type': 'comisaria',
      'phone': '(01) 536-1842',
      'emergency_phone': '105',
    },
    {
      'name': 'Comisaría PNP Universitaria',
      'lat': -11.9475,
      'lng': -77.0600,
      'type': 'comisaria',
      'phone': '(01) 536-4321',
      'emergency_phone': '105',
    },
  ];

  /// Colegios y centros educativos dentro del área real de Collique.
  static List<Map<String, dynamic>> get schools => [
    {
      'name': 'I.E. N° 2099 - Collique',
      'lat': -11.9165,
      'lng': -77.0325,
      'type': 'colegio',
    },
    {
      'name': 'I.E. San Martín de Porres',
      'lat': -11.9120,
      'lng': -77.0275,
      'type': 'colegio',
    },
    {
      'name': 'I.E. Santa Rosa de Collique',
      'lat': -11.9095,
      'lng': -77.0315,
      'type': 'colegio',
    },
    {
      'name': 'I.E. Los Olivos de Collique',
      'lat': -11.9195,
      'lng': -77.0300,
      'type': 'colegio',
    },
    {
      'name': 'I.E. Señor de los Milagros',
      'lat': -11.9135,
      'lng': -77.0200,
      'type': 'colegio',
    },
    {
      'name': 'I.E. Mariscal Cáceres',
      'lat': -11.9165,
      'lng': -77.0370,
      'type': 'colegio',
    },
  ];

  /// Parques y áreas verdes de Collique (Parque Central en su ubicación real).
  static List<Map<String, dynamic>> get parks => [
    {
      'name': 'Parque Central de Collique',
      'lat': -11.9068,
      'lng': -77.0347,
      'type': 'parque',
    },
    {
      'name': 'Parque Túpac Amaru',
      'lat': -11.9160,
      'lng': -77.0365,
      'type': 'parque',
    },
    {
      'name': 'Parque Los Olivos',
      'lat': -11.9190,
      'lng': -77.0300,
      'type': 'parque',
    },
    {
      'name': 'Parque Collique Alto',
      'lat': -11.9075,
      'lng': -77.0210,
      'type': 'parque',
    },
    {
      'name': 'Losa Deportiva Collique',
      'lat': -11.9110,
      'lng': -77.0235,
      'type': 'parque',
    },
  ];

  /// Mercados reales de Collique y zonas cercanas.
  static List<Map<String, dynamic>> get markets => [
    {
      'name': 'Mercado Central 1° Zona de Collique',
      'lat': -11.9154,
      'lng': -77.0330,
      'type': 'mercado',
    },
    {
      'name': 'Mercado 12 de Febrero',
      'lat': -11.9116,
      'lng': -77.0220,
      'type': 'mercado',
    },
    {
      'name': 'Mercado Santa Luzmila',
      'lat': -11.9440,
      'lng': -77.0655,
      'type': 'mercado',
    },
  ];

  /// Centros de salud reales de Collique (Hospital Bernales en su ubicación).
  static List<Map<String, dynamic>> get healthCenters => [
    {
      'name': 'Hospital Sergio Bernales',
      'lat': -11.91390,
      'lng': -77.03928,
      'type': 'hospital',
      'phone': '(01) 558-0101',
    },
    {
      'name': 'Policlínico Cesmyn',
      'lat': -11.9136,
      'lng': -77.0399,
      'type': 'postas',
      'phone': '(01) 558-0200',
    },
    {
      'name': 'Centro de Salud Collique',
      'lat': -11.9145,
      'lng': -77.0320,
      'type': 'postas',
      'phone': '(01) 558-0300',
    },
    {
      'name': 'Centro de Salud Santa Luzmila',
      'lat': -11.9445,
      'lng': -77.0655,
      'type': 'postas',
      'phone': '(01) 536-1800',
    },
  ];

  /// Todos los POIs combinados en una sola lista para renderizar en el mapa.
  static List<Map<String, dynamic>> get allPois => [
    ...policeStations,
    ...schools,
    ...parks,
    ...markets,
    ...healthCenters,
  ];

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
  static Map<String, dynamic>? findNearestPoi(double lat, double lng,
      {String? type}) {
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

  /// Colores distintivos para cada zona (14 colores, gradiente de azul a rojo).
  static List<Color> get zoneColors => [
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

  // ============================================================
  // CÁLCULO DE DISTANCIA (Fórmula de Haversine)
  // ============================================================

  /// Calcula la distancia en metros entre dos puntos geográficos.
  static double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // metros

    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
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
