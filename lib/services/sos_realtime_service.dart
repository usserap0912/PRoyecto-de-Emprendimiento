import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:safezone/models/sos_alert.dart';
import 'package:safezone/services/supabase_service.dart';

class SosRealtimeService {
  static final SosRealtimeService _instance = SosRealtimeService._internal();
  factory SosRealtimeService() => _instance;
  SosRealtimeService._internal();

  final SupabaseService _supabase = SupabaseService();

  final ValueNotifier<List<SosAlert>> activeAlerts =
      ValueNotifier<List<SosAlert>>(const []);
  final ValueNotifier<SosAlert?> incomingAlert = ValueNotifier<SosAlert?>(null);
  final ValueNotifier<bool> hasConnectionError = ValueNotifier<bool>(false);

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Timer? _expiryTimer;
  static const int _notificationHistoryLimit = 256;
  final Set<String> _notifiedAlertIds = <String>{};
  String? _currentUserCode;
  String? _notificationOwnerUserCode;

  void start({required String currentUserCode}) {
    _prepareNotificationOwner(currentUserCode);
    stop(clearState: true);
    _currentUserCode = currentUserCode;

    try {
      _subscription = _supabase.client
          .from(_supabase.sosAlertsTable)
          .stream(primaryKey: ['id'])
          .eq('status', 'activo')
          .order('created_at', ascending: false)
          .listen(
            _handleSnapshot,
            onError: (Object error) {
              debugPrint('SosRealtimeService stream error: $error');
              hasConnectionError.value = true;
            },
          );
      _expiryTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _removeExpiredAlerts(),
      );
    } catch (error) {
      debugPrint('SosRealtimeService.start error: $error');
      hasConnectionError.value = true;
    }
  }

  @visibleForTesting
  List<SosAlert> parseVisibleAlerts(
    List<Map<String, dynamic>> rows, {
    required String currentUserCode,
    required DateTime now,
  }) {
    return rows
        .map(SosAlert.tryFromMap)
        .whereType<SosAlert>()
        .where(
          (alert) =>
              alert.userCode != currentUserCode &&
              alert.isPubliclyActiveAt(now),
        )
        .toList(growable: false);
  }

  void _handleSnapshot(List<Map<String, dynamic>> rows) {
    final userCode = _currentUserCode;
    if (userCode == null) return;

    _processSnapshot(
      rows,
      currentUserCode: userCode,
      now: DateTime.now().toUtc(),
    );
  }

  SosAlert? _processSnapshot(
    List<Map<String, dynamic>> rows, {
    required String currentUserCode,
    required DateTime now,
  }) {
    _prepareNotificationOwner(currentUserCode);

    final alerts = parseVisibleAlerts(
      rows,
      currentUserCode: currentUserCode,
      now: now,
    );
    hasConnectionError.value = false;
    activeAlerts.value = alerts;

    final newAlerts = alerts
        .where((alert) => !_notifiedAlertIds.contains(alert.id))
        .toList(growable: false);
    if (newAlerts.isEmpty) return null;

    for (final alert in newAlerts) {
      _rememberNotifiedAlert(alert.id);
    }
    final incoming = newAlerts.first;
    if (kDebugMode) debugPrint('[SOS][received] alertId=${incoming.id}');
    incomingAlert.value = incoming;
    return incoming;
  }

  @visibleForTesting
  SosAlert? processSnapshotForTesting(
    List<Map<String, dynamic>> rows, {
    required String currentUserCode,
    required DateTime now,
  }) {
    _currentUserCode = currentUserCode;
    return _processSnapshot(rows, currentUserCode: currentUserCode, now: now);
  }

  void _prepareNotificationOwner(String currentUserCode) {
    if (_notificationOwnerUserCode == currentUserCode) return;
    _notificationOwnerUserCode = currentUserCode;
    _notifiedAlertIds.clear();
  }

  void _rememberNotifiedAlert(String alertId) {
    _notifiedAlertIds.add(alertId);
    while (_notifiedAlertIds.length > _notificationHistoryLimit) {
      _notifiedAlertIds.remove(_notifiedAlertIds.first);
    }
  }

  void _removeExpiredAlerts() {
    final now = DateTime.now().toUtc();
    final visible = activeAlerts.value
        .where((alert) => alert.isPubliclyActiveAt(now))
        .toList(growable: false);
    if (visible.length != activeAlerts.value.length) {
      activeAlerts.value = visible;
    }
  }

  void stop({bool clearState = false, bool clearNotificationHistory = false}) {
    _subscription?.cancel();
    _subscription = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _currentUserCode = null;
    if (clearNotificationHistory) {
      _notifiedAlertIds.clear();
      _notificationOwnerUserCode = null;
    }
    if (clearState) {
      activeAlerts.value = const [];
      incomingAlert.value = null;
      hasConnectionError.value = false;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    stop(clearState: true, clearNotificationHistory: true);
  }
}
