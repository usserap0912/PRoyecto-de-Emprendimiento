import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ============================================================
// NOTIFICATION SERVICE
// ============================================================
// Muestra notificaciones locales cuando hay reportes de robo
// u otras alertas de seguridad en la zona del vecino.
// ============================================================

/// Servicio de notificaciones locales push.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Inicializa el plugin de notificaciones.
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      // The app-wide in-app SOS banner is the Web fallback. Do not call a
      // native-only plugin implementation from Edge/Chrome.
      return;
    }

    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(initSettings);

      // Crear canal para alertas de seguridad
      const androidChannel = AndroidNotificationChannel(
        'safezone_alerts',
        'Alertas de SafeZone',
        description: 'Reportes de seguridad y alertas vecinales',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(androidChannel);

      _initialized = true;
      debugPrint('NotificationService: Inicializado correctamente');
    } catch (e) {
      debugPrint('NotificationService: Error inicializando: $e');
    }
  }

  /// Muestra una notificación local de alerta de seguridad.
  Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb || !_initialized) return;

    try {
      final vibrationPattern = Int64List(4)
        ..[0] = 0
        ..[1] = 500
        ..[2] = 300
        ..[3] = 500;

      final androidDetails = AndroidNotificationDetails(
        'safezone_alerts',
        'Alertas de SafeZone',
        channelDescription: 'Reportes de seguridad y alertas vecinales',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        showWhen: true,
        enableLights: true,
        vibrationPattern: vibrationPattern,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(id, title, body, details, payload: payload);
      debugPrint('NotificationService: Notificación mostrada: $title');
    } catch (e) {
      debugPrint('NotificationService: Error mostrando notificación: $e');
    }
  }

  /// Muestra una notificación de robo reportado.
  Future<void> showRoboAlert({
    required int zone,
    required String timeAgo,
    required String distance,
    int similarReports = 0,
  }) async {
    final title = '🚨 Robo reportado en Zona $zone';
    final body = similarReports > 1
        ? 'Hace $timeAgo · A $distance · $similarReports reportes similares hoy'
        : 'Hace $timeAgo · A $distance de ti';

    await showAlertNotification(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      body: body,
      payload: 'robo_zone_$zone',
    );
  }

  /// Muestra una notificación de alerta S.O.S. activa.
  Future<void> showSosAlert({
    required String userCode,
    String? areaLabel,
  }) async {
    final title = '🚨 ¡Alerta S.O.S. activa!';
    final body = areaLabel == null
        ? 'Un vecino necesita ayuda. Abre SafeZone para ver la ubicación aproximada.'
        : 'Un vecino necesita ayuda en $areaLabel.';

    await showAlertNotification(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      body: body,
      payload: 'sos_$userCode',
    );
  }
}
