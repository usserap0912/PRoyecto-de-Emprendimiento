import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

// ============================================================
// CONFIGURACIÓN DEL MAPA — GOOGLE MAPS (Maps SDK for Android)
// ============================================================
// La app corre solo en Android. El mapa nativo de Google usa la API
// key definida en AndroidManifest via ${MAPS_API_KEY}, inyectada desde
// android/app/build.gradle.kts leyendo la variable de entorno
// MAPS_API_KEY (nunca hardcodeada en el repositorio).
//
//   MAPS_API_KEY=AIza... flutter run         (bash / WSL / CI)
//   $env:MAPS_API_KEY="AIza..."; flutter run (PowerShell)
//
// El uso móvil del mapa (mapa, marcadores, círculos) es gratuito para
// este tipo de app, por eso no hay proveedor de tiles ni key en código.
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

  // ----------------------------------------------------------
  // CONVERSIÓN: latlong2 (modelos/servicios internos) → Google
  // ----------------------------------------------------------
  // Los modelos y servicios del proyecto usan `LatLng` de latlong2. El
  // widget GoogleMap requiere los tipos nativos de google_maps_flutter,
  // así que la conversión vive aquí para que las pantallas no mezclen
  // ambos paquetes.
  static gmaps.LatLng g(LatLng point) =>
      gmaps.LatLng(point.latitude, point.longitude);

  static gmaps.LatLngBounds gBounds(MapBounds bounds) =>
      gmaps.LatLngBounds(
        southwest:
            gmaps.LatLng(bounds.south, bounds.west),
        northeast:
            gmaps.LatLng(bounds.north, bounds.east),
      );
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
