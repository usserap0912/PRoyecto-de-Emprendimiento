import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:safezone/models/territorial_zone.dart';

/// Acceso único a las divisiones territoriales almacenadas como GeoJSON.
class TerritoryService {
  static const String verifiedZonesAsset =
      'assets/territory/collique_verified_zones.geojson';
  static const String candidateZonesAsset =
      'assets/territory/collique_candidate_zones.geojson';

  List<TerritorialZone>? _verifiedZonesCache;
  List<TerritorialZone>? _candidateZonesCache;
  List<TerritorialZone>? _selectableZonesCache;

  Future<List<TerritorialZone>> loadVerifiedZones() async {
    final cached = _verifiedZonesCache;
    if (cached != null) return cached;

    final contents = await rootBundle.loadString(verifiedZonesAsset);
    final zones = parseVerifiedZones(contents);
    _verifiedZonesCache = zones;
    return zones;
  }

  Future<List<TerritorialZone>> loadCandidateZones() async {
    final cached = _candidateZonesCache;
    if (cached != null) return cached;

    final contents = await rootBundle.loadString(candidateZonesAsset);
    final zones = parseFeatureCollection(contents);
    _candidateZonesCache = zones;
    return zones;
  }

  /// Zonas reconocidas que pueden elegirse aunque no todas tengan geometría.
  Future<List<TerritorialZone>> loadSelectableZones() async {
    final cached = _selectableZonesCache;
    if (cached != null) return cached;

    final verified = await loadVerifiedZones();
    final withoutGeometry = await loadCandidateZones();
    final zones = combineSelectableZones(<TerritorialZone>[
      ...verified,
      ...withoutGeometry,
    ]);
    _selectableZonesCache = zones;
    return zones;
  }

  static List<TerritorialZone> parseVerifiedZones(String contents) {
    final zones =
        parseFeatureCollection(contents)
            .where((zone) => zone.isVerifiedProductionPoint)
            .toList(growable: false)
          ..sort((a, b) => a.zoneNumber.compareTo(b.zoneNumber));

    const expectedZoneNumbers = <int>{1, 2, 3, 4, 5, 6};
    final actualZoneNumbers = zones.map((zone) => zone.zoneNumber).toSet();
    if (zones.length != expectedZoneNumbers.length ||
        !actualZoneNumbers.containsAll(expectedZoneNumbers)) {
      throw const FormatException(
        'El mapa requiere exactamente los puntos territoriales verificados I–VI.',
      );
    }

    for (final zone in zones) {
      final lat = zone.latitude!;
      final lng = zone.longitude!;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        throw FormatException('Coordenadas inválidas para ${zone.name}.');
      }
      if (zone.geometryRole != 'reference_point' ||
          zone.boundaryStatus != 'not_available') {
        throw FormatException(
          '${zone.name} no está declarado como punto referencial sin límites.',
        );
      }
    }

    return List<TerritorialZone>.unmodifiable(zones);
  }

  static List<TerritorialZone> combineSelectableZones(
    Iterable<TerritorialZone> source,
  ) {
    final zones =
        source.where((zone) => zone.selectionVisible).toList(growable: false)
          ..sort((a, b) => a.zoneNumber.compareTo(b.zoneNumber));

    const expectedZoneNumbers = <int>{1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    final actualZoneNumbers = zones.map((zone) => zone.zoneNumber).toSet();
    if (zones.length != expectedZoneNumbers.length ||
        !actualZoneNumbers.containsAll(expectedZoneNumbers)) {
      throw const FormatException(
        'El selector requiere las zonas reconocidas I–X sin inventar geometría.',
      );
    }

    return List<TerritorialZone>.unmodifiable(zones);
  }

  static List<TerritorialZone> parseFeatureCollection(String contents) {
    final decoded = jsonDecode(contents);
    if (decoded is! Map || decoded['type'] != 'FeatureCollection') {
      throw const FormatException(
        'El archivo territorial no es FeatureCollection.',
      );
    }

    final rawFeatures = decoded['features'];
    if (rawFeatures is! List) {
      throw const FormatException('El GeoJSON no contiene una lista features.');
    }

    return List<TerritorialZone>.unmodifiable(
      rawFeatures.map((rawFeature) {
        if (rawFeature is! Map) {
          throw const FormatException('Feature territorial inválido.');
        }
        return TerritorialZone.fromGeoJsonFeature(
          Map<String, dynamic>.from(rawFeature),
        );
      }),
    );
  }
}
