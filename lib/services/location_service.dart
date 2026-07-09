import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  /// Obtiene la posición actual del dispositivo
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

  /// Comisarías y puntos policiales cercanos a Collique, Comas
  static List<Map<String, dynamic>> get policeStations => [
    {
      'name': 'Comisaría de Collique',
      'lat': -11.9335,
      'lng': -77.0730,
      'type': 'comisaria',
    },
    {
      'name': 'Comisaría de Santa Luzmila',
      'lat': -11.9380,
      'lng': -77.0590,
      'type': 'comisaria',
    },
    {
      'name': 'Comisaría de La Pascana',
      'lat': -11.9450,
      'lng': -77.0430,
      'type': 'comisaria',
    },
    {
      'name': 'Puesto Policial - Av. Túpac Amaru',
      'lat': -11.9250,
      'lng': -77.0670,
      'type': 'puesto',
    },
    {
      'name': 'Serenazgo de Collique',
      'lat': -11.9360,
      'lng': -77.0760,
      'type': 'serenazgo',
    },
    {
      'name': 'Comisaría de Comas',
      'lat': -11.9410,
      'lng': -77.0650,
      'type': 'comisaria',
    },
    {
      'name': 'Base Policial - Collique Alto',
      'lat': -11.9440,
      'lng': -77.0830,
      'type': 'puesto',
    },
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
