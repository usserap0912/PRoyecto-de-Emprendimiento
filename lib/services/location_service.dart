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

  // Coordenadas aproximadas de Collique, Comas
  static const double colliqueLat = -11.9325;
  static const double colliqueLng = -77.0734;

  /// Coordenadas de las zonas de Collique (aproximadas)
  static Map<int, Map<String, double>> get zoneCoordinates => {
    1: {'lat': -11.9280, 'lng': -77.0700},
    2: {'lat': -11.9300, 'lng': -77.0720},
    3: {'lat': -11.9325, 'lng': -77.0734},
    4: {'lat': -11.9350, 'lng': -77.0750},
    5: {'lat': -11.9370, 'lng': -77.0770},
    6: {'lat': -11.9295, 'lng': -77.0690},
    7: {'lat': -11.9340, 'lng': -77.0780},
  };
}
