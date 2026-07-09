import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Servicio centralizado para gestionar permisos de la app SafeZone.
///
/// Verifica y solicita [Permission.locationWhenInUse], [Permission.camera]
/// y [Permission.photos] (Android 13+ / iOS).
///
/// Retorna [false] si algún permiso fue denegado permanentemente,
/// para que la UI pueda mostrar un SnackBar informativo.
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// Verifica y solicita todos los permisos necesarios para SafeZone.
  ///
  /// - Si ya están otorgados, no hace nada.
  /// - Si están denegados, los solicita.
  /// - Si fueron denegados permanentemente, retorna `false`.
  ///
  /// [showGoToSettings] Si es `true`, abre la configuración del sistema
  /// cuando un permiso fue denegado permanentemente (útil para botón
  /// "Abrir Configuración" en la UI).
  Future<bool> requestAllPermissions({bool showGoToSettings = false}) async {
    try {
      // 1. Ubicación (cuando la app está en uso)
      final locationStatus = await Permission.locationWhenInUse.status;
      if (locationStatus.isDenied) {
        final result = await Permission.locationWhenInUse.request();
        if (result.isPermanentlyDenied) {
          if (showGoToSettings) await openAppSettings();
          return false;
        }
      } else if (locationStatus.isPermanentlyDenied) {
        if (showGoToSettings) await openAppSettings();
        return false;
      }

      // 2. Cámara
      final cameraStatus = await Permission.camera.status;
      if (cameraStatus.isDenied) {
        final result = await Permission.camera.request();
        if (result.isPermanentlyDenied) {
          if (showGoToSettings) await openAppSettings();
          return false;
        }
      } else if (cameraStatus.isPermanentlyDenied) {
        if (showGoToSettings) await openAppSettings();
        return false;
      }

      // 3. Fotos (Android 13+ usa Permission.photos en vez de storage)
      // Intentamos con Permission.photos primero; si falla, usamos Permission.storage
      try {
        final photosStatus = await Permission.photos.status;
        if (photosStatus.isDenied) {
          final result = await Permission.photos.request();
          if (result.isPermanentlyDenied) {
            if (showGoToSettings) await openAppSettings();
            return false;
          }
        } else if (photosStatus.isPermanentlyDenied) {
          if (showGoToSettings) await openAppSettings();
          return false;
        }
      } catch (_) {
        // Fallback para Android < 13: usar Permission.storage
        final storageStatus = await Permission.storage.status;
        if (storageStatus.isDenied) {
          final result = await Permission.storage.request();
          if (result.isPermanentlyDenied) {
            if (showGoToSettings) await openAppSettings();
            return false;
          }
        } else if (storageStatus.isPermanentlyDenied) {
          if (showGoToSettings) await openAppSettings();
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('PermissionService.requestAllPermissions error: $e');
      return false;
    }
  }

  /// Verifica solo el permiso de ubicación (útil para mapas / reportes).
  Future<bool> hasLocationPermission() async {
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted;
  }

  /// Verifica solo el permiso de cámara (útil para tomar fotos/video).
  Future<bool> hasCameraPermission() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Verifica solo el permiso de fotos/galería.
  Future<bool> hasPhotosPermission() async {
    try {
      return await Permission.photos.isGranted;
    } catch (_) {
      return await Permission.storage.isGranted;
    }
  }

  /// Abre la configuración de la app en el sistema.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
