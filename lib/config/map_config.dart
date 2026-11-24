import 'package:latlong2/latlong.dart';

// ============================================================
// CONFIGURACIÓN DEL MAPA — OPENSTREETMAP (flutter_map)
// ============================================================
// La app corre solo en Android y dibuja el mapa con tiles públicos de
// OpenStreetMap. No requiere API key, cuenta ni facturación.
//
// El User-Agent que exige la política de uso de OSM se configura en el
// TileLayer de cada pantalla (userAgentPackageName).
// ============================================================
class MapConfig {
  const MapConfig._();

  /// Ventana operativa amplia del mapa.
  ///
  /// No representa el límite territorial de Collique ni se renderiza como
  /// polígono. Conservada para impedir que pantallas heredadas se desplacen
  /// accidentalmente a otra parte de Lima.
  static final MapBounds colliqueBounds = MapBounds(
    south: -11.945,
    west: -77.055,
    north: -11.905,
    east: -76.985,
  );

  /// Fallback heredado para pantallas que todavía requieren un punto inicial.
  /// El mapa de riesgo usa los bounds calculados desde el GeoJSON verificado.
  static const LatLng colliqueCenter = LatLng(-11.9330, -77.0230);
}

/// Límites geográficos mínimos propios, descritos con las esquinas
/// noreste / suroeste, independientes del paquete de mapas que se use
/// para renderizarlos.
class MapBounds {
  const MapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;
}
