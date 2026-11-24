import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:safezone/config/risk_map_camera_config.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/services/territory_service.dart';

void main() {
  test(
    'initial camera uses I–VI and the verified hospital grounds only',
    () async {
      final geoJson = await File(
        TerritoryService.verifiedZonesAsset,
      ).readAsString();
      final zones = TerritoryService.parseVerifiedZones(geoJson);

      final points = RiskMapCameraConfig.referencePoints(
        zones: zones,
        verifiedHealthCenters: LocationService.healthCenters,
      );
      final bounds = RiskMapCameraConfig.initialBounds(
        zones: zones,
        verifiedHealthCenters: LocationService.healthCenters,
      );
      final center = RiskMapCameraConfig.initialCenter(
        zones: zones,
        verifiedHealthCenters: LocationService.healthCenters,
      );

      expect(points, hasLength(7));
      for (final zone in zones) {
        expect(points, contains(zone.referencePoint), reason: zone.name);
      }
      expect(points, contains(const LatLng(-11.9141196, -77.0376892)));
      expect(bounds.west, closeTo(-77.0376892, 1e-9));
      expect(bounds.east, closeTo(-77.0037646, 1e-9));
      expect(bounds.south, closeTo(-11.915714, 1e-9));
      expect(bounds.north, closeTo(-11.9119415, 1e-9));

      // El centro inicial debe caer dentro de los bounds calculados.
      expect(center.latitude >= bounds.south, isTrue);
      expect(center.latitude <= bounds.north, isTrue);
      expect(center.longitude >= bounds.west, isTrue);
      expect(center.longitude <= bounds.east, isTrue);
    },
  );

  test('initial camera config exposes map fit parameters', () async {
    expect(RiskMapCameraConfig.initialZoom, inInclusiveRange(11, 19));

    final geoJson = await File(
      TerritoryService.verifiedZonesAsset,
    ).readAsString();
    final zones = TerritoryService.parseVerifiedZones(geoJson);
    // El padding se pasa a CameraFit.bounds y debe respetar el panel
    // superior y la leyenda inferior.
    expect(RiskMapCameraConfig.initialPadding.vertical, greaterThan(0));
    // La cámara inicial solo se construye con datos verificados.
    expect(
      () => RiskMapCameraConfig.initialBounds(
        zones: zones,
        verifiedHealthCenters: LocationService.healthCenters,
      ),
      returnsNormally,
    );
  });

  test('RiskMapScreen does not reuse the legacy Collique constraint', () async {
    final source = await File(
      'lib/screens/map/risk_map_screen.dart',
    ).readAsString();

    expect(
      source,
      isNot(contains('MapConfig.colliqueConstraint')),
    );
    expect(source, contains('FlutterMap('));
    expect(source, contains('CameraFit.bounds('));
    expect(source, contains('if (!_isMapReady || bounds == null) return;'));
    expect(source, isNot(contains('google_maps_flutter')));
  });
}
