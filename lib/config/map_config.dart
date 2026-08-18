import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ============================================================
// CONFIGURACIÓN DEL MAPA — MAPTILER (plan gratuito)
// ============================================================
// Para usar MapTiler:
//   1. Regístrate gratis en https://cloud.maptiler.com/
//   2. Copia tu API key en: https://cloud.maptiler.com/account/keys/
//   3. Pégala aquí abajo:
//
//      static const String mapTilerApiKey = 'TU_API_KEY_AQUI';
//
// También puedes pasarla al compilar con:
//   flutter run --dart-define=MAPTILER_API_KEY=TU_API_KEY_AQUI
//
// Mientras la key esté vacía, la app usa OpenStreetMap automáticamente
// (gratis, sin key), para que el mapa funcione siempre.
// ============================================================
class MapConfig {
  static const String mapTilerApiKey = String.fromEnvironment(
    'MAPTILER_API_KEY',
    defaultValue: 'ZW9P49AqLdJrN5uEqdfl', // API key de MapTiler del proyecto
  );

  static bool get hasMapTilerKey => mapTilerApiKey.trim().isNotEmpty;

  /// Estilo claro principal. Con key → MapTiler streets; sin key → OpenStreetMap.
  static String get lightTileUrl => hasMapTilerKey
      ? 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}{r}.png?key=$mapTilerApiKey'
      : fallbackTileUrl;

  /// URL de respaldo: OpenStreetMap (gratis, sin key, siempre disponible).
  /// Se usa cuando el proveedor principal falla en tiempo de ejecución
  /// (key agotada, revocada o error de red del proveedor).
  static String get fallbackTileUrl =>
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Estilo oscuro.
  /// NOTA: el plan gratuito de MapTiler NO incluye estilos oscuros
  /// (dark-v2 responde 404), por eso usamos siempre el estilo claro.
  static String get darkTileUrl => lightTileUrl;

  /// Atribución requerida por el proveedor activo.
  static String get attribution => hasMapTilerKey
      ? '© MapTiler © OpenStreetMap contributors'
      : '© OpenStreetMap contributors';

  /// Ventana operativa amplia del mapa.
  ///
  /// No representa el límite territorial de Collique ni se renderiza como
  /// polígono. Se conserva para impedir que pantallas heredadas se desplacen
  /// accidentalmente a otra parte de Lima.
  static final LatLngBounds colliqueBounds = LatLngBounds(
    const LatLng(-11.945, -77.055),
    const LatLng(-11.905, -76.985),
  );

  /// Fallback heredado para pantallas que todavía requieren un punto inicial.
  /// El mapa de riesgo usa bounds calculados desde el GeoJSON verificado.
  static const LatLng colliqueCenter = LatLng(-11.9330, -77.0230);

  /// Restricción operativa: el centro de cámara permanece dentro de la
  /// ventana amplia definida arriba. No expresa pertenencia territorial.
  ///
  /// Se usa [CameraConstraint.containCenter] en lugar de `contain` porque
  /// `contain` devuelve `null` en pantallas anchas y dispara un `assert`
  /// de flutter_map que deja el mapa en negro / crashea la pantalla.
  static CameraConstraint get colliqueConstraint =>
      CameraConstraint.containCenter(bounds: colliqueBounds);
}
