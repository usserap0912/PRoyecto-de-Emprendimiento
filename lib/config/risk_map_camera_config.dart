import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:safezone/models/territorial_zone.dart';

/// Configuración de cámara exclusiva del mapa de riesgo.
///
/// Los bounds se usan solo para encuadrar puntos de referencia. No representan
/// ni restringen el límite territorial de Collique.
class RiskMapCameraConfig {
  const RiskMapCameraConfig._();

  static const CameraConstraint cameraConstraint =
      CameraConstraint.unconstrained();
  static const EdgeInsets initialPadding = EdgeInsets.fromLTRB(36, 72, 36, 100);

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

  static LatLngBounds initialBounds({
    required List<TerritorialZone> zones,
    required Iterable<Map<String, dynamic>> verifiedHealthCenters,
  }) {
    return LatLngBounds.fromPoints(
      referencePoints(
        zones: zones,
        verifiedHealthCenters: verifiedHealthCenters,
      ),
    );
  }

  static CameraFit initialCameraFit({
    required List<TerritorialZone> zones,
    required Iterable<Map<String, dynamic>> verifiedHealthCenters,
  }) {
    return CameraFit.bounds(
      bounds: initialBounds(
        zones: zones,
        verifiedHealthCenters: verifiedHealthCenters,
      ),
      padding: initialPadding,
      maxZoom: 15.5,
      minZoom: 11,
    );
  }
}
