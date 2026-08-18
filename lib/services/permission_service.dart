import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

enum AppPermissionResult { granted, denied, permanentlyDenied, unavailable }

/// Requests one capability at the moment it is used. The UI is responsible for
/// explaining why before invoking a request method.
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  Future<AppPermissionResult> requestLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return AppPermissionResult.unavailable;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => AppPermissionResult.granted,
        LocationPermission.deniedForever =>
          AppPermissionResult.permanentlyDenied,
        LocationPermission.denied => AppPermissionResult.denied,
        LocationPermission.unableToDetermine => AppPermissionResult.unavailable,
      };
    } catch (error) {
      debugPrint('PermissionService.location error: $error');
      return AppPermissionResult.unavailable;
    }
  }

  Future<AppPermissionResult> requestCameraPermission() async {
    if (kIsWeb) return AppPermissionResult.granted;
    return _request(handler.Permission.camera);
  }

  Future<AppPermissionResult> requestPhotosPermission() async {
    // Browsers and Android's system photo picker mediate access per selection;
    // there is no broad library permission to request in advance.
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
      return AppPermissionResult.granted;
    }
    try {
      return _request(handler.Permission.photos);
    } catch (_) {
      return _request(handler.Permission.storage);
    }
  }

  Future<AppPermissionResult> _request(handler.Permission permission) async {
    try {
      var status = await permission.status;
      if (status.isDenied) status = await permission.request();
      if (status.isGranted || status.isLimited) {
        return AppPermissionResult.granted;
      }
      if (status.isPermanentlyDenied || status.isRestricted) {
        return AppPermissionResult.permanentlyDenied;
      }
      return AppPermissionResult.denied;
    } catch (error) {
      debugPrint('PermissionService request error: $error');
      return AppPermissionResult.unavailable;
    }
  }

  @Deprecated('Solicita cada permiso únicamente cuando la función lo necesita.')
  Future<bool> requestAllPermissions({bool showGoToSettings = false}) async {
    final location = await requestLocationPermission();
    final camera = await requestCameraPermission();
    final photos = await requestPhotosPermission();
    final granted =
        location == AppPermissionResult.granted &&
        camera == AppPermissionResult.granted &&
        photos == AppPermissionResult.granted;
    if (!granted && showGoToSettings) await openSettings();
    return granted;
  }

  Future<bool> hasLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasCameraPermission() async {
    if (kIsWeb) return true;
    return handler.Permission.camera.isGranted;
  }

  Future<bool> hasPhotosPermission() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) return true;
    try {
      return await handler.Permission.photos.isGranted;
    } catch (_) {
      return handler.Permission.storage.isGranted;
    }
  }

  Future<bool> openSettings() async {
    if (kIsWeb) return false;
    return handler.openAppSettings();
  }
}
