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
      1: 'Av. Túpac Amaru - Entrada',
      2: 'Mercado Collique',
      3: 'Parque Central',
      4: 'Los Olivos',
      5: 'Av. Collique',
      6: 'Sector Nuevo',
      7: 'Alto Collique',
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

  // Coordenadas del centro del mapa (Av. Revolución, Collique)
  // Centro ajustado para abarcar las 14 zonas completas
  static const double colliqueLat = -11.9368;
  static const double colliqueLng = -77.0770;

  /// Coordenadas de las 14 zonas de Collique (aproximadas)
  static Map<int, Map<String, double>> get zoneCoordinates => {
    1: {'lat': -11.9280, 'lng': -77.0700},  // Av. Túpac Amaru - Entrada
    2: {'lat': -11.9300, 'lng': -77.0720},  // Mercado Collique
    3: {'lat': -11.9325, 'lng': -77.0734},  // Parque Central
    4: {'lat': -11.9350, 'lng': -77.0750},  // Los Olivos
    5: {'lat': -11.9370, 'lng': -77.0770},  // Av. Collique
    6: {'lat': -11.9295, 'lng': -77.0690},  // Sector Nuevo
    7: {'lat': -11.9340, 'lng': -77.0780},  // Alto Collique
    8: {'lat': -11.9360, 'lng': -77.0790},  // Sector 8
    9: {'lat': -11.9380, 'lng': -77.0805},  // Sector 9
    10: {'lat': -11.9395, 'lng': -77.0818}, // Sector 10
    11: {'lat': -11.9410, 'lng': -77.0830}, // Sector 11
    12: {'lat': -11.9425, 'lng': -77.0842}, // Sector 12
    13: {'lat': -11.9440, 'lng': -77.0852}, // Sector 13
    14: {'lat': -11.9455, 'lng': -77.0860}, // Zona más alta
  };

  // Coordenadas de puntos de referencia en Collique
  static const double hospitalLat = -11.9312;
  static const double hospitalLng = -77.0698;
  static const double comisariaLat = -11.9335;
  static const double comisariaLng = -77.0730;
  static const double museoLat = -11.9265;
  static const double museoLng = -77.0665;

  // ================================================================
  // POLÍGONOS DE ZONAS
  // ================================================================
  /// Polígonos aproximados de las 14 zonas de Collique (vértices en sentido horario).
  /// Cada zona es un cuadrilátero alrededor de su centro.
  static Map<int, List<Map<String, double>>> get zonePolygons => {
    1: [
      {'lat': -11.9260, 'lng': -77.0715},
      {'lat': -11.9275, 'lng': -77.0685},
      {'lat': -11.9295, 'lng': -77.0690},
      {'lat': -11.9290, 'lng': -77.0720},
    ],
    2: [
      {'lat': -11.9285, 'lng': -77.0735},
      {'lat': -11.9290, 'lng': -77.0705},
      {'lat': -11.9315, 'lng': -77.0710},
      {'lat': -11.9310, 'lng': -77.0740},
    ],
    3: [
      {'lat': -11.9305, 'lng': -77.0750},
      {'lat': -11.9315, 'lng': -77.0720},
      {'lat': -11.9340, 'lng': -77.0725},
      {'lat': -11.9335, 'lng': -77.0755},
    ],
    4: [
      {'lat': -11.9330, 'lng': -77.0765},
      {'lat': -11.9340, 'lng': -77.0735},
      {'lat': -11.9365, 'lng': -77.0740},
      {'lat': -11.9360, 'lng': -77.0770},
    ],
    5: [
      {'lat': -11.9350, 'lng': -77.0785},
      {'lat': -11.9365, 'lng': -77.0755},
      {'lat': -11.9385, 'lng': -77.0760},
      {'lat': -11.9380, 'lng': -77.0790},
    ],
    6: [
      {'lat': -11.9275, 'lng': -77.0705},
      {'lat': -11.9285, 'lng': -77.0675},
      {'lat': -11.9305, 'lng': -77.0680},
      {'lat': -11.9300, 'lng': -77.0710},
    ],
    7: [
      {'lat': -11.9325, 'lng': -77.0795},
      {'lat': -11.9335, 'lng': -77.0765},
      {'lat': -11.9360, 'lng': -77.0770},
      {'lat': -11.9355, 'lng': -77.0800},
    ],
    8: [
      {'lat': -11.9345, 'lng': -77.0805},
      {'lat': -11.9355, 'lng': -77.0775},
      {'lat': -11.9375, 'lng': -77.0780},
      {'lat': -11.9370, 'lng': -77.0810},
    ],
    9: [
      {'lat': -11.9365, 'lng': -77.0820},
      {'lat': -11.9375, 'lng': -77.0790},
      {'lat': -11.9395, 'lng': -77.0795},
      {'lat': -11.9390, 'lng': -77.0825},
    ],
    10: [
      {'lat': -11.9380, 'lng': -77.0835},
      {'lat': -11.9395, 'lng': -77.0805},
      {'lat': -11.9415, 'lng': -77.0810},
      {'lat': -11.9410, 'lng': -77.0840},
    ],
    11: [
      {'lat': -11.9395, 'lng': -77.0845},
      {'lat': -11.9410, 'lng': -77.0815},
      {'lat': -11.9425, 'lng': -77.0820},
      {'lat': -11.9420, 'lng': -77.0850},
    ],
    12: [
      {'lat': -11.9410, 'lng': -77.0855},
      {'lat': -11.9425, 'lng': -77.0825},
      {'lat': -11.9440, 'lng': -77.0830},
      {'lat': -11.9435, 'lng': -77.0860},
    ],
    13: [
      {'lat': -11.9425, 'lng': -77.0865},
      {'lat': -11.9435, 'lng': -77.0835},
      {'lat': -11.9455, 'lng': -77.0840},
      {'lat': -11.9450, 'lng': -77.0870},
    ],
    14: [
      {'lat': -11.9440, 'lng': -77.0875},
      {'lat': -11.9450, 'lng': -77.0845},
      {'lat': -11.9465, 'lng': -77.0850},
      {'lat': -11.9460, 'lng': -77.0880},
    ],
  };

  // ================================================================
  // PUNTOS DE REFERENCIA (POIs)
  // ================================================================

  /// Comisarías y puntos policiales cercanos a Collique, Comas.
  static List<Map<String, dynamic>> get policeStations => [
    {
      'name': 'Comisaría de Collique',
      'lat': -11.9335,
      'lng': -77.0730,
      'type': 'comisaria',
      'phone': '(01) 558-2798',
      'emergency_phone': '105',
    },
    {
      'name': 'Comisaría de Santa Luzmila',
      'lat': -11.9380,
      'lng': -77.0590,
      'type': 'comisaria',
      'phone': '(01) 536-1842',
      'emergency_phone': '105',
    },
    {
      'name': 'Comisaría de La Pascana',
      'lat': -11.9450,
      'lng': -77.0430,
      'type': 'comisaria',
      'phone': '(01) 562-3456',
      'emergency_phone': '105',
    },
    {
      'name': 'Puesto Policial - Av. Túpac Amaru',
      'lat': -11.9250,
      'lng': -77.0670,
      'type': 'puesto',
      'phone': '(01) 558-2901',
      'emergency_phone': '105',
    },
    {
      'name': 'Serenazgo de Collique',
      'lat': -11.9360,
      'lng': -77.0760,
      'type': 'serenazgo',
      'phone': '(01) 575-4321',
      'emergency_phone': '116',
    },
    {
      'name': 'Comisaría de Comas',
      'lat': -11.9410,
      'lng': -77.0650,
      'type': 'comisaria',
      'phone': '(01) 536-4321',
      'emergency_phone': '105',
    },
    {
      'name': 'Base Policial - Collique Alto',
      'lat': -11.9440,
      'lng': -77.0830,
      'type': 'puesto',
      'phone': '(01) 558-3700',
      'emergency_phone': '105',
    },
  ];

  /// Colegios y centros educativos en Collique.
  static List<Map<String, dynamic>> get schools => [
    {
      'name': 'I.E. N° 2099 - Collique',
      'lat': -11.9305,
      'lng': -77.0710,
      'type': 'colegio',
    },
    {
      'name': 'I.E. San Martín de Porres',
      'lat': -11.9340,
      'lng': -77.0745,
      'type': 'colegio',
    },
    {
      'name': 'I.E. Santa Rosa de Collique',
      'lat': -11.9375,
      'lng': -77.0780,
      'type': 'colegio',
    },
    {
      'name': 'I.E. Los Olivos de Collique',
      'lat': -11.9360,
      'lng': -77.0755,
      'type': 'colegio',
    },
    {
      'name': 'I.E. Señor de los Milagros',
      'lat': -11.9400,
      'lng': -77.0810,
      'type': 'colegio',
    },
    {
      'name': 'I.E. Mariscal Cáceres',
      'lat': -11.9285,
      'lng': -77.0695,
      'type': 'colegio',
    },
  ];

  /// Parques y áreas verdes de Collique.
  static List<Map<String, dynamic>> get parks => [
    {
      'name': 'Parque Central de Collique',
      'lat': -11.9325,
      'lng': -77.0734,
      'type': 'parque',
    },
    {
      'name': 'Parque Los Olivos',
      'lat': -11.9355,
      'lng': -77.0755,
      'type': 'parque',
    },
    {
      'name': 'Parque Túpac Amaru',
      'lat': -11.9270,
      'lng': -77.0690,
      'type': 'parque',
    },
    {
      'name': 'Parque Collique Alto',
      'lat': -11.9430,
      'lng': -77.0835,
      'type': 'parque',
    },
    {
      'name': 'Losa Deportiva Collique',
      'lat': -11.9385,
      'lng': -77.0795,
      'type': 'parque',
    },
  ];

  /// Mercados y centros comerciales de Collique.
  static List<Map<String, dynamic>> get markets => [
    {
      'name': 'Mercado de Collique',
      'lat': -11.9300,
      'lng': -77.0720,
      'type': 'mercado',
    },
    {
      'name': 'Mercado Santa Luzmila',
      'lat': -11.9375,
      'lng': -77.0600,
      'type': 'mercado',
    },
    {
      'name': 'Mercado Los Olivos',
      'lat': -11.9350,
      'lng': -77.0750,
      'type': 'mercado',
    },
  ];

  /// Centros de salud y postas médicas.
  static List<Map<String, dynamic>> get healthCenters => [
    {
      'name': 'Hospital Sergio Bernales',
      'lat': -11.9312,
      'lng': -77.0698,
      'type': 'hospital',
      'phone': '(01) 558-0101',
    },
    {
      'name': 'Centro de Salud Collique',
      'lat': -11.9330,
      'lng': -77.0730,
      'type': 'postas',
      'phone': '(01) 558-0300',
    },
    {
      'name': 'Posta Médica Los Olivos',
      'lat': -11.9365,
      'lng': -77.0745,
      'type': 'postas',
      'phone': '(01) 558-0400',
    },
    {
      'name': 'Centro de Salud Santa Luzmila',
      'lat': -11.9385,
      'lng': -77.0595,
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
