import 'package:latlong2/latlong.dart';

/// División territorial descrita por una entidad GeoJSON.
///
/// Una coordenada solo es una referencia cartográfica. La pertenencia a una
/// zona no puede calcularse hasta disponer de límites oficiales verificables.
class TerritorialZone {
  const TerritorialZone({
    required this.id,
    required this.zoneNumber,
    required this.displayLabel,
    required this.name,
    required this.nameVariants,
    required this.divisionType,
    required this.geometryRole,
    required this.boundaryStatus,
    required this.verificationStatus,
    required this.confidence,
    required this.sourceRefs,
    required this.productionVisible,
    required this.selectionVisible,
    required this.verifiedAt,
    required this.geometryType,
    required this.longitude,
    required this.latitude,
  });

  final String id;
  final int zoneNumber;
  final String displayLabel;
  final String name;
  final List<String> nameVariants;
  final String divisionType;
  final String geometryRole;
  final String boundaryStatus;
  final String verificationStatus;
  final String confidence;
  final List<String> sourceRefs;
  final bool productionVisible;
  final bool selectionVisible;
  final String? verifiedAt;
  final String? geometryType;
  final double? longitude;
  final double? latitude;

  bool get isVerifiedProductionPoint =>
      productionVisible &&
      verificationStatus == 'verified' &&
      geometryType == 'Point' &&
      longitude != null &&
      latitude != null;

  LatLng? get referencePoint {
    final lat = latitude;
    final lng = longitude;
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  factory TerritorialZone.fromGeoJsonFeature(Map<String, dynamic> feature) {
    if (feature['type'] != 'Feature') {
      throw const FormatException('La entidad territorial no es un Feature.');
    }

    final rawProperties = feature['properties'];
    if (rawProperties is! Map) {
      throw const FormatException('El Feature no contiene properties válidas.');
    }
    final properties = Map<String, dynamic>.from(rawProperties);

    String requiredString(String key) {
      final value = properties[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('La propiedad territorial "$key" no es válida.');
      }
      return value;
    }

    List<String> stringList(String key) {
      final value = properties[key];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('La propiedad territorial "$key" no es válida.');
      }
      return List<String>.unmodifiable(value.cast<String>());
    }

    String? geometryType;
    double? longitude;
    double? latitude;
    final rawGeometry = feature['geometry'];
    if (rawGeometry != null) {
      if (rawGeometry is! Map) {
        throw const FormatException('La geometría territorial no es válida.');
      }
      final geometry = Map<String, dynamic>.from(rawGeometry);
      geometryType = geometry['type'] as String?;
      final coordinates = geometry['coordinates'];
      if (geometryType == 'Point') {
        if (coordinates is! List ||
            coordinates.length < 2 ||
            coordinates[0] is! num ||
            coordinates[1] is! num) {
          throw const FormatException(
            'El Point territorial debe usar [longitud, latitud].',
          );
        }
        longitude = (coordinates[0] as num).toDouble();
        latitude = (coordinates[1] as num).toDouble();
      }
    }

    final zoneNumber = properties['zoneNumber'];
    final productionVisible = properties['productionVisible'];
    final selectionVisible = properties['selectionVisible'];
    if (zoneNumber is! int ||
        productionVisible is! bool ||
        selectionVisible is! bool) {
      throw const FormatException(
        'zoneNumber, productionVisible o selectionVisible no tienen el tipo esperado.',
      );
    }

    final verifiedAtValue = properties['verifiedAt'];
    if (verifiedAtValue != null && verifiedAtValue is! String) {
      throw const FormatException('verifiedAt debe ser texto o null.');
    }

    return TerritorialZone(
      id: requiredString('id'),
      zoneNumber: zoneNumber,
      displayLabel: requiredString('displayLabel'),
      name: requiredString('name'),
      nameVariants: stringList('nameVariants'),
      divisionType: requiredString('divisionType'),
      geometryRole: requiredString('geometryRole'),
      boundaryStatus: requiredString('boundaryStatus'),
      verificationStatus: requiredString('verificationStatus'),
      confidence: requiredString('confidence'),
      sourceRefs: stringList('sourceRefs'),
      productionVisible: productionVisible,
      selectionVisible: selectionVisible,
      verifiedAt: verifiedAtValue as String?,
      geometryType: geometryType,
      longitude: longitude,
      latitude: latitude,
    );
  }
}
