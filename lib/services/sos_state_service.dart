import 'package:flutter/foundation.dart';

// ============================================================
// SOS STATE SERVICE — Estado compartido de la alerta S.O.S.
// ============================================================
// Permite que otras pantallas (ej: el Mapa de Riesgo) se enteren
// cuando el usuario activa o desactiva una alerta S.O.S., para
// reaccionar en tiempo real (ej: parpadeo del punto de ubicación).
// ============================================================

class SosStateService {
  SosStateService._internal();

  static final SosStateService _instance = SosStateService._internal();

  factory SosStateService() => _instance;

  /// Notifica a los listeners cuando cambia el estado del S.O.S.
  final ValueNotifier<bool> isSosActive = ValueNotifier<bool>(false);

  bool get active => isSosActive.value;

  /// Marca la alerta S.O.S. como activa (true) o inactiva (false).
  void setActive(bool value) {
    if (isSosActive.value != value) {
      isSosActive.value = value;
    }
  }

  void dispose() {
    isSosActive.dispose();
  }
}
