import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safezone/services/sound_service.dart';

// ============================================================
// POWER SAVER SERVICE — Modo Ahorro (batería / datos)
// ============================================================
//
// Reduce el consumo de batería y datos móviles:
//   🎵  Desactiva efectos de sonido
//   ✨  Desactiva animaciones decorativas (partículas, pulsos, etc.)
//   🖼️  Desactiva precarga de imágenes en streams
//   📡  Reduce frecuencia de actualizaciones en tiempo real
//   🤟  Desactiva vibración háptica
//   🎬  Reduce calidad de animaciones (menos fps decorativos)
//
// Persiste la preferencia en SharedPreferences y se puede activar
// manualmente o de forma automática cuando la batería está baja.
// ============================================================

/// Configuración del Modo Ahorro.
class PowerSaverConfig {
  final bool disableSounds;
  final bool disableAnimations;
  final bool disableParticles;
  final bool disableHaptics;
  final bool disableImagePreload;
  final bool reduceRealtimeUpdates;
  final bool reduceAnimationQuality;

  const PowerSaverConfig({
    this.disableSounds = true,
    this.disableAnimations = true,
    this.disableParticles = true,
    this.disableHaptics = true,
    this.disableImagePreload = true,
    this.reduceRealtimeUpdates = true,
    this.reduceAnimationQuality = true,
  });

  static const PowerSaverConfig none = PowerSaverConfig(
    disableSounds: false,
    disableAnimations: false,
    disableParticles: false,
    disableHaptics: false,
    disableImagePreload: false,
    reduceRealtimeUpdates: false,
    reduceAnimationQuality: false,
  );

  static const PowerSaverConfig full = PowerSaverConfig();

  PowerSaverConfig copyWith({
    bool? disableSounds,
    bool? disableAnimations,
    bool? disableParticles,
    bool? disableHaptics,
    bool? disableImagePreload,
    bool? reduceRealtimeUpdates,
    bool? reduceAnimationQuality,
  }) {
    return PowerSaverConfig(
      disableSounds: disableSounds ?? this.disableSounds,
      disableAnimations: disableAnimations ?? this.disableAnimations,
      disableParticles: disableParticles ?? this.disableParticles,
      disableHaptics: disableHaptics ?? this.disableHaptics,
      disableImagePreload: disableImagePreload ?? this.disableImagePreload,
      reduceRealtimeUpdates:
          reduceRealtimeUpdates ?? this.reduceRealtimeUpdates,
      reduceAnimationQuality:
          reduceAnimationQuality ?? this.reduceAnimationQuality,
    );
  }
}

/// Servicio singleton que gestiona el Modo Ahorro de SafeZone.
class PowerSaverService {
  static final PowerSaverService _instance = PowerSaverService._internal();
  factory PowerSaverService() => _instance;
  PowerSaverService._internal();

  static const String _prefsKey = 'power_saver_enabled';
  static const String _prefsModeKey = 'power_saver_auto';

  bool _isEnabled = false;
  bool _autoMode = true; // Por defecto: automático
  PowerSaverConfig _config = PowerSaverConfig.none;
  bool _initialized = false;

  // ValueNotifier para notificar cambios a los widgets
  final ValueNotifier<bool> onChangeNotifier = ValueNotifier<bool>(false);
  bool get isEnabled => _isEnabled;
  bool get autoMode => _autoMode;
  PowerSaverConfig get config => _config;

  // Callbacks para notificar a servicios
  VoidCallback? onPowerSaverChanged;

  /// Inicializa el servicio: carga preferencia y configura el SoundService.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefsKey) ?? false;
      _autoMode = prefs.getBool(_prefsModeKey) ?? true;

      // Actualizar configuración según el estado
      _applyConfig(_isEnabled);

      _initialized = true;
      debugPrint(
          'PowerSaverService: inicializado (enabled=$_isEnabled, auto=$_autoMode)');
    } catch (e) {
      debugPrint('PowerSaverService: error en initialize: $e');
      _initialized = true;
    }
  }

  /// Activa o desactiva el Modo Ahorro manualmente.
  /// Al activarlo manualmente, desactiva el modo automático.
  Future<void> setEnabled(bool value) async {
    if (_isEnabled == value) return;
    _isEnabled = value;

    // Si el usuario activa/desactiva manualmente, desactivar auto
    _autoMode = false;

    _applyConfig(value);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
      await prefs.setBool(_prefsModeKey, false);
    } catch (e) {
      debugPrint('PowerSaverService: error guardando preferencia: $e');
    }

    onChangeNotifier.value = value;
    onPowerSaverChanged?.call();
  }

  /// Alterna el estado actual.
  Future<void> toggle() async {
    await setEnabled(!_isEnabled);
  }

  /// Activa o reactiva el modo automático (basado en batería/bajo consumo).
  Future<void> setAutoMode(bool value) async {
    _autoMode = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsModeKey, value);
    } catch (e) {
      debugPrint('PowerSaverService: error guardando auto mode: $e');
    }
  }

  /// Aplica la configuración a los servicios globales.
  void _applyConfig(bool enabled) {
    if (enabled) {
      _config = PowerSaverConfig.full;
      // Mutear sonidos globalmente
      SoundService().setMuted(true);
    } else {
      _config = PowerSaverConfig.none;
      SoundService().setMuted(false);
    }
  }

  /// Limpia recursos al cerrar la app.
  void dispose() {
    onChangeNotifier.dispose();
  }

  // ============================================================
  // MÉTODOS DE CONSULTA PARA WIDGETS
  // ============================================================

  /// ¿Deben omitirse animaciones decorativas?
  bool get shouldSkipAnimations => _isEnabled && _config.disableAnimations;

  /// ¿Deben omitirse efectos de partículas?
  bool get shouldSkipParticles => _isEnabled && _config.disableParticles;

  /// ¿Deben omitirse vibraciones hápticas?
  bool get shouldSkipHaptics => _isEnabled && _config.disableHaptics;

  /// ¿Debe omitirse precarga de imágenes?
  bool get shouldSkipImagePreload => _isEnabled && _config.disableImagePreload;

  /// ¿Debe reducirse la frecuencia de actualizaciones?
  bool get shouldReduceRealtime =>
      _isEnabled && _config.reduceRealtimeUpdates;

  /// ¿Debe reducirse la calidad de animaciones?
  bool get shouldReduceQuality =>
      _isEnabled && _config.reduceAnimationQuality;
}


