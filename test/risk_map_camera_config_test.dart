import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
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

      expect(points, hasLength(7));
      for (final zone in zones) {
        expect(points, contains(zone.referencePoint), reason: zone.name);
      }
      expect(points, contains(const LatLng(-11.9141196, -77.0376892)));
      expect(bounds.west, -77.0376892);
      expect(bounds.east, -77.0037646);
      expect(bounds.south, -11.915714);
      expect(bounds.north, -11.9119415);
    },
  );

  test(
    'risk map navigation is unconstrained and fit options are preserved',
    () async {
      expect(
        RiskMapCameraConfig.cameraConstraint,
        const CameraConstraint.unconstrained(),
      );

      final geoJson = await File(
        TerritoryService.verifiedZonesAsset,
      ).readAsString();
      final zones = TerritoryService.parseVerifiedZones(geoJson);
      final fit = RiskMapCameraConfig.initialCameraFit(
        zones: zones,
        verifiedHealthCenters: LocationService.healthCenters,
      );

      expect(fit, isA<FitBounds>());
      final fitBounds = fit as FitBounds;
      expect(fitBounds.padding, RiskMapCameraConfig.initialPadding);
      expect(fitBounds.maxZoom, 15.5);
      expect(fitBounds.minZoom, 11);
    },
  );

  test('RiskMapScreen does not reuse the legacy Collique constraint', () async {
    final source = await File(
      'lib/screens/map/risk_map_screen.dart',
    ).readAsString();

    expect(
      source,
      contains('cameraConstraint: RiskMapCameraConfig.cameraConstraint'),
    );
    expect(
      source,
      isNot(contains('cameraConstraint: MapConfig.colliqueConstraint')),
    );
    expect(source, contains('if (!_isMapReady || cameraFit == null) return;'));
  });
}
