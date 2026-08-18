import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/territorial_zone.dart';
import 'package:safezone/services/territory_service.dart';

void main() {
  late String verifiedGeoJson;
  late String candidateGeoJson;
  late List<TerritorialZone> productionZones;
  late List<TerritorialZone> zonesWithoutGeometry;
  late List<TerritorialZone> selectableZones;

  setUpAll(() async {
    verifiedGeoJson = await File(
      TerritoryService.verifiedZonesAsset,
    ).readAsString();
    candidateGeoJson = await File(
      TerritoryService.candidateZonesAsset,
    ).readAsString();
    productionZones = TerritoryService.parseVerifiedZones(verifiedGeoJson);
    zonesWithoutGeometry = TerritoryService.parseFeatureCollection(
      candidateGeoJson,
    );
    selectableZones = TerritoryService.combineSelectableZones(<TerritorialZone>[
      ...productionZones,
      ...zonesWithoutGeometry,
    ]);
  });

  group('territorio conservador de Collique', () {
    test('el mapa contiene únicamente puntos territoriales I–VI', () {
      expect(productionZones, hasLength(6));
      expect(
        productionZones.map((zone) => zone.zoneNumber),
        orderedEquals(<int>[1, 2, 3, 4, 5, 6]),
      );
      for (final zone in productionZones) {
        expect(zone.isVerifiedProductionPoint, isTrue, reason: zone.name);
        expect(zone.geometryRole, 'reference_point');
        expect(zone.boundaryStatus, 'not_available');
        expect(zone.sourceRefs, isNotEmpty);
        expect(zone.selectionVisible, isTrue);
        expect(zone.verifiedAt, '2026-08-17');
      }
    });

    test('VII–X se conservan reconocidas y sin geometría inventada', () {
      expect(zonesWithoutGeometry, hasLength(4));
      expect(
        zonesWithoutGeometry.map((zone) => zone.zoneNumber),
        orderedEquals(<int>[7, 8, 9, 10]),
      );
      for (final zone in zonesWithoutGeometry) {
        expect(zone.productionVisible, isFalse, reason: zone.name);
        expect(zone.selectionVisible, isTrue, reason: zone.name);
        expect(zone.geometryType, isNull, reason: zone.name);
        expect(zone.referencePoint, isNull, reason: zone.name);
        expect(zone.geometryRole, 'not_available');
        expect(zone.boundaryStatus, 'not_available');
      }
    });

    test('el selector admite I–X sin exigir coordenadas', () {
      expect(selectableZones, hasLength(10));
      expect(
        selectableZones.map((zone) => zone.zoneNumber),
        orderedEquals(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      expect(
        selectableZones
            .where((zone) => zone.zoneNumber >= 7)
            .every((zone) => zone.referencePoint == null),
        isTrue,
      );
    });

    test('XI–XIV y el sistema artificial Z1–Z14 no existen', () {
      final zoneNumbers = selectableZones
          .map((zone) => zone.zoneNumber)
          .toSet();
      expect(zoneNumbers.intersection(<int>{11, 12, 13, 14}), isEmpty);
      expect(selectableZones, hasLength(10));
    });

    test('I–VI usan coordenadas válidas en orden longitud, latitud', () {
      final rawCollection = jsonDecode(verifiedGeoJson) as Map<String, dynamic>;
      final rawFeatures = rawCollection['features'] as List<dynamic>;

      for (var index = 0; index < productionZones.length; index++) {
        final zone = productionZones[index];
        final feature = rawFeatures[index] as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>;
        final coordinates = geometry['coordinates'] as List<dynamic>;

        expect(geometry['type'], 'Point', reason: zone.name);
        expect(coordinates, hasLength(2), reason: zone.name);
        expect(coordinates[0], zone.longitude, reason: zone.name);
        expect(coordinates[1], zone.latitude, reason: zone.name);
        expect(zone.longitude, inInclusiveRange(-180, 180));
        expect(zone.latitude, inInclusiveRange(-90, 90));
      }
    });

    test('ninguna colección territorial utiliza Polygon', () {
      expect(
        productionZones.every((zone) => zone.geometryType == 'Point'),
        isTrue,
      );
      expect(verifiedGeoJson, isNot(contains('"Polygon"')));
      expect(candidateGeoJson, isNot(contains('"Polygon"')));
    });

    test('el mapa no renderiza rectángulos territoriales heredados', () async {
      final mapSource = await File(
        'lib/screens/map/risk_map_screen.dart',
      ).readAsString();
      final locationSource = await File(
        'lib/services/location_service.dart',
      ).readAsString();

      expect(mapSource, isNot(contains('PolygonLayer(')));
      expect(mapSource, isNot(contains('LocationService.zonePolygons')));
      expect(mapSource, isNot(contains('List.generate(14')));
      expect(locationSource, isNot(contains('zonePolygons')));
      expect(locationSource, isNot(contains('zoneCoordinates')));
    });
  });
}
