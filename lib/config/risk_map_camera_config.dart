import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:safezone/config/map_config.dart';
import 'package:safezone/models/territorial_zone.dart';

/// Configuración de cámara exclusiva del mapa de riesgo.
///
/// Los bounds se usan solo para encuadrar puntos de referencia. No representan
/// ni restringen el límite territorial de Collique.
class RiskMapCameraConfig {
  const RiskMapCameraConfig._();

  /// Padding usado al encuadrar las referencias territoriales con
  /// [CameraUpdate.newLatLngBounds] (el padding es simétrico en Google Maps).
  static const EdgeInsets initialPadding = EdgeInsets.fromLTRB(36, 72, 36, 100);

  /// Zoom de arranque mientras cargan las zonas; apenas el mapa está listo se
  /// anima a los bounds reales, así que este valor solo evita un flash feo.
  static const double initialZoom = 13.0;

  static List<LatLng> referencePoints({
    required List<TerritorialZone> zones,
    required Iterable<Map<String, dynamic>> verifiedHealthCenters,
  }) {
    final points = zones
        .map((zone) => zone.referencePoint)
        .whereType<LatLng>()
        .toList(growable: true);

    final hospitals = verifiedHealthCenters.where(
      (poi) =>
          poi['name'] == 'Hospital Nacional Sergio E. Bernales' &&
          poi['type'] == 'hospital' &&
          poi['verified'] == true &&
          poi['verificationStatus'] == 'VERIFIED' &&
          poi['productionVisible'] == true &&
          poi['coordinateRole'] == 'building_footprint_center',
    );
    if (hospitals.length != 1) {
      throw StateError(
        'La cámara requiere una única referencia verificada del recinto del '
        'Hospital Nacional Sergio E. Bernales.',
      );
    }

    final hospital = hospitals.single;
    points.add(LatLng(hospital['lat'] as double, hospital['lng'] as double));

    return List<LatLng>.unmodifiable(points);
  }

  static MapBounds initialBounds({
    required List<TerritorialZone> zones,
    required Iterable<Map<String, dynamic>> verifiedHealthCenters,
  }) {
    final points = referencePoints(
      zones: zones,
      verifiedHealthCenters: verifiedHealthCenters,
    );
    return MapBounds(
      south: points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
      west: points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
      north: points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
      east: points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
    );
  }

  static LatLng initialCenter({
    required List<TerritorialZone> zones,
    required Iterable<Map<String, dynamic>> verifiedHealthCenters,
  }) {
    final bounds = initialBounds(
      zones: zones,
      verifiedHealthCenters: verifiedHealthCenters,
    );
    return LatLng(
      (bounds.south + bounds.north) / 2,
      (bounds.west + bounds.east) / 2,
    );
  }
}
