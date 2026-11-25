import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:safezone/services/notification_service.dart';
import 'package:safezone/services/sos_realtime_service.dart';
import 'package:safezone/services/sound_service.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// PUSH SERVICE — Firebase Cloud Messaging
// ============================================================
// Es lo que permite que un S.O.S. o un reporte llegue al celular
// AUNQUE LA APP ESTÉ CERRADA. Firebase mantiene la conexión del
// sistema y despierta la app; aquí registramos el teléfono y
// mostramos el aviso cuando la app está abierta.
// ============================================================

class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  /// Tabla donde se guarda el token FCM de cada teléfono.
  static const String deviceTokensTable = 'device_tokens';

  /// Edge Function que envía el push al resto de vecinos.
  static const String sendPushFunction = 'send-push';

  final SupabaseService _supabase = SupabaseService();

  bool _initialized = false;
  String? _userCode;
  int? _zone;
  String? _token;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;

  bool get isInitialized => _initialized;

  /// Arranca Firebase. Nunca lanza: si algo falla la app sigue funcionando
  /// con el realtime de siempre.
  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Android 13+ ya lo pide NotificationService; iOS lo cubre arriba.
      await NotificationService().initialize();

      // Con la app abierta mostramos nosotros el aviso (evita duplicados
      // del sistema y nos deja sonar la alarma MP3).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      _messageSubscription = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
        _persistToken,
      );

      _token = await messaging.getToken();
      _initialized = true;
      debugPrint('[PUSH] Firebase listo');
      await _syncToken();
    } catch (error) {
      debugPrint('[PUSH] Firebase no disponible: $error');
    }
  }

  /// Guarda el código de usuario para asociarle el token del teléfono.
  Future<void> register({required String userCode, required int zone}) async {
    _userCode = userCode;
    _zone = zone;
    if (!_initialized) return;
    if (_token == null) {
      try {
        _token = await FirebaseMessaging.instance.getToken();
      } catch (error) {
        debugPrint('[PUSH] getToken error: $error');
      }
    }
    await _syncToken();
  }

  /// Borra el token del servidor (p. ej. al cambiar de usuario en el móvil).
  Future<void> unregister() async {
    final token = _token;
    _userCode = null;
    if (token == null) return;
    try {
      await _supabase.client
          .from(deviceTokensTable)
          .delete()
          .eq('token', token)
          .timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint('[PUSH] unregister error: $error');
    }
  }

  Future<void> _syncToken() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    await _persistToken(token);
  }

  Future<void> _persistToken(String token) async {
    final userCode = _userCode;
    if (userCode == null || token.isEmpty) return;
    _token = token;
    try {
      await _supabase.client
          .from(deviceTokensTable)
          .upsert({
            'token': token,
            'user_code': userCode,
            'zone': _zone,
            'platform': 'android',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'token')
          .timeout(const Duration(seconds: 10));
      debugPrint('[PUSH] token asociado a $userCode');
    } catch (error) {
      // Si la migración aún no se ejecutó, no rompemos nada.
      debugPrint('[PUSH] no se pudo guardar el token: $error');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Con la app abierta el realtime ya avisa (y suena la alarma); aquí solo
    // cubrimos el S.O.S. que el realtime no alcanzó a notificar.
    final type = message.data['type'];
    if (type != 'sos') return;

    final alertId = message.data['alertId'] ?? '';
    if (alertId.isNotEmpty &&
        SosRealtimeService().wasRecentlyNotified(alertId)) {
      return;
    }

    unawaited(SoundService().playSosReceivedAlert());
    unawaited(
      NotificationService().showSosAlert(
        userCode: message.data['userCode'] ?? '',
        areaLabel: message.data['area'],
      ),
    );
  }

  /// Pide al servidor que avise al resto de vecinos por push.
  /// Es "fire and forget": si falla, el realtime sigue cubriendo a los
  /// usuarios que tienen la app abierta.
  Future<void> sendAlertPush({
    required String type,
    required String alertId,
    required String userCode,
    int? zone,
    String? category,
  }) async {
    if (kIsWeb || !_initialized) return;
    try {
      await Supabase.instance.client.functions
          .invoke(
            sendPushFunction,
            body: {
              'type': type,
              'alertId': alertId,
              'userCode': userCode,
              'zone': zone,
              'category': category,
            },
          )
          .timeout(const Duration(seconds: 12));
    } catch (error) {
      debugPrint('[PUSH] envío falló (no bloquea): $error');
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _tokenRefreshSubscription?.cancel();
    _messageSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _messageSubscription = null;
    _initialized = false;
    _userCode = null;
    _zone = null;
    _token = null;
  }
}
