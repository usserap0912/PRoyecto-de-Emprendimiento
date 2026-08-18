import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/services/location_service.dart';
import 'package:safezone/services/poi_catalog.dart';

void main() {
  group('catálogo conservador de POI de Collique', () {
    test('producción contiene exclusivamente los 22 POI VERIFIED', () {
      final pois = LocationService.allPois;

      expect(pois, hasLength(22));
      for (final poi in pois) {
        expect(LocationService.isProductionPoi(poi), isTrue);
        expect(poi['verified'], isTrue, reason: poi['name'] as String);
        expect(
          poi['verificationStatus'],
          PoiCatalog.verifiedStatus,
          reason: poi['name'] as String,
        );
        expect(poi['productionVisible'], isTrue);
        expect(poi['source'], isNotEmpty);
        expect(poi['sourceId'], isNotEmpty);
        expect(poi['coordinateRole'], isNotEmpty);
        expect(poi['verifiedAt'], '2026-08-17');
        expect(poi['lat'], isA<double>());
        expect(poi['lng'], isA<double>());
      }
    });

    test('solo se crean categorías con POI verificados reales', () {
      final categories = LocationService.allPois
          .map((poi) => poi['category'] as String)
          .toSet();

      expect(categories, <String>{
        'security',
        'health',
        'markets',
        'education',
        'fuel',
        'culture',
        'social_equipment',
        'cemetery',
      });
      expect(LocationService.transportation, isEmpty);
      expect(LocationService.parks, isEmpty);
    });

    test('ningún registro no productivo puede aparecer en producción', () {
      final productionIdentities = LocationService.allPois
          .map((poi) => '${poi['name']}|${poi['lat']}|${poi['lng']}')
          .toSet();

      expect(LocationService.partiallyVerifiedPlaces, isNotEmpty);
      expect(LocationService.unverifiedPlaces, isNotEmpty);
      expect(LocationService.rejectedPlaces, isNotEmpty);

      for (final poi in LocationService.auditedPlaces) {
        expect(poi['verified'], isFalse, reason: poi['name'] as String);
        expect(poi['productionVisible'], isFalse);
        expect(poi['verificationStatus'], isNot(PoiCatalog.verifiedStatus));
        expect(
          productionIdentities,
          isNot(contains('${poi['name']}|${poi['lat']}|${poi['lng']}')),
        );
      }
    });

    test('solo aparecen las dos comisarías verificadas de Collique', () {
      final stations = LocationService.policeStations;
      expect(stations, hasLength(2));

      final mainStation = stations.singleWhere(
        (poi) => poi['name'] == 'Comisaría PNP Collique',
      );
      expect(mainStation['lat'], -11.9130804);
      expect(mainStation['lng'], -77.0161997);
      expect(mainStation['address'], 'Av. Revolución 2591, IV Zona');

      final familyStation = stations.singleWhere(
        (poi) => poi['name'] == 'Comisaría PNP de Familia Collique',
      );
      expect(familyStation['lat'], -11.9129766);
      expect(familyStation['lng'], -77.0103792);

      final productionNames = LocationService.allPois
          .map((poi) => poi['name'])
          .toSet();
      expect(productionNames, isNot(contains('Comisaría PNP La Pascana')));
      expect(productionNames, isNot(contains('Comisaría PNP Santa Luzmila')));
      expect(productionNames, isNot(contains('Comisaría PNP Universitaria')));
      expect(
        LocationService.allPois.any(
          (poi) => poi['lat'] == -11.92138 && poi['lng'] == -77.02264,
        ),
        isFalse,
      );
    });

    test(
      'la comisaría más cercana usa exclusivamente el catálogo VERIFIED',
      () {
        final nearestMain = LocationService.findNearestStation(
          -11.9130804,
          -77.0161997,
        );
        expect(nearestMain['name'], 'Comisaría PNP Collique');
        expect(nearestMain['distance_meters'], closeTo(0, 0.01));

        final nearestFamily = LocationService.findNearestStation(
          -11.9129766,
          -77.0103792,
        );
        expect(nearestFamily['name'], 'Comisaría PNP de Familia Collique');
        expect(nearestFamily['emergency_phone'], '105');
      },
    );

    test('hospital usa el recinto y no afirma un acceso verificado', () {
      final hospital = LocationService.healthCenters.singleWhere(
        (poi) => poi['type'] == 'hospital',
      );

      expect(hospital['lat'], -11.9141196);
      expect(hospital['lng'], -77.0376892);
      expect(hospital['coordinateRole'], 'building_footprint_center');
      expect(hospital.containsKey('accessSourceId'), isFalse);
    });

    test('grifos usan razones sociales canónicas de OSINERGMIN', () {
      final fuelStations = LocationService.fuelStations;
      expect(fuelStations, hasLength(5));
      expect(
        fuelStations.map((poi) => poi['name']),
        containsAll(<String>[
          'Full Oils Petro S.A.C.',
          'Corporación Megu S.A.C.',
          'Distribuidora e Importadora M&G S.A.C.',
          'ROAN Inversiones S.A.C.',
        ]),
      );
      expect(
        fuelStations.any(
          (poi) => (poi['name'] as String).toUpperCase().contains('PECSA'),
        ),
        isFalse,
      );
    });

    test('museo conserva una sola coordenada centralizada', () {
      expect(LocationService.museums, hasLength(1));
      final museum = LocationService.museums.single;
      expect(museum['name'], 'Museo de los Colli');
      expect(museum['lat'], -11.9113963);
      expect(museum['lng'], -77.0261052);
      expect(museum['sourceId'], 'node/1932068160');
    });

    test('el mapa renderiza solo LocationService.allPois validado', () async {
      final source = await File(
        'lib/screens/map/risk_map_screen.dart',
      ).readAsString();

      expect(source, contains('LocationService.allPois'));
      expect(source, contains('.where(LocationService.isProductionPoi)'));
      expect(source, isNot(contains('LocationService.unverifiedPlaces')));
      expect(source, isNot(contains('LocationService.rejectedPlaces')));
      expect(source, isNot(contains('_filtrarComisariasCercanas')));
    });

    test('detección territorial sigue desactivada sin límites oficiales', () {
      expect(LocationService.detectZone(-11.9152621, -77.0349165), isNull);
      expect(LocationService.zoneName(1), 'Collique - Zona I');
      expect(LocationService.zoneName(10), 'Collique - Zona X');
    });
  });
}
