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

  /// Canal de máxima prioridad usado también por las notificaciones push
  /// (la Edge Function envía este channel_id a Firebase).
  static const String sosChannelId = 'safezone_sos_v2';
  static const String alertsChannelId = 'safezone_alerts';

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

      final androidImplementation = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      // Crear canal para alertas de seguridad
      const androidChannel = AndroidNotificationChannel(
        'safezone_alerts',
        'Alertas de SafeZone',
        description: 'Reportes de seguridad y alertas vecinales',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      // Canal exclusivo del S.O.S.: máxima prioridad y la alarma MP3 real
      // (res/raw/alarma_recepcion.mp3) para que suene y vibre aunque el
      // celular esté bloqueado o la app cerrada. El id lleva sufijo _v2
      // porque Android no permite cambiar el sonido de un canal existente.
      final sosChannel = AndroidNotificationChannel(
        sosChannelId,
        'Alertas S.O.S. de SafeZone',
        description: 'Avisos urgentes de vecinos que activaron el S.O.S.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarma_recepcion'),
        enableVibration: true,
        enableLights: true,
        vibrationPattern: Int64List.fromList(<int>[0, 800, 400, 800, 400, 800]),
      );

      await androidImplementation?.createNotificationChannel(androidChannel);
      await androidImplementation?.createNotificationChannel(sosChannel);

      // Android 13+ exige autorización explícita; sin ella las
      // notificaciones locales nunca se muestran.
      await androidImplementation?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

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
    bool critical = false,
  }) async {
    if (kIsWeb || !_initialized) return;

    try {
      final vibrationPattern = Int64List(4)
        ..[0] = 0
        ..[1] = 500
        ..[2] = 300
        ..[3] = 500;

      final androidDetails = AndroidNotificationDetails(
        critical ? sosChannelId : alertsChannelId,
        critical ? 'Alertas S.O.S. de SafeZone' : 'Alertas de SafeZone',
        channelDescription: critical
            ? 'Avisos urgentes de vecinos que activaron el S.O.S.'
            : 'Reportes de seguridad y alertas vecinales',
        importance: critical ? Importance.max : Importance.high,
        priority: critical ? Priority.max : Priority.high,
        category: critical
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/ic_launcher',
        sound: critical
            ? const RawResourceAndroidNotificationSound('alarma_recepcion')
            : null,
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
      critical: true,
    );
  }
}
