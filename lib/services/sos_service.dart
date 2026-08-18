import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:safezone/models/sos_session.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

abstract interface class SosGateway {
  Future<SosPublishResult> publish({
    required String activationId,
    required String userCode,
    required int zone,
    required SosCoordinates publicCoordinates,
  });

  Future<void> updateLocation({
    required String alertId,
    required String userCode,
    required SosCoordinates publicCoordinates,
  });

  Future<void> finish({
    required String alertId,
    required String userCode,
    String? reportId,
  });
}

class SupabaseSosGateway implements SosGateway {
  static const Duration operationTimeout = Duration(seconds: 12);

  final SupabaseService _supabase;

  SupabaseSosGateway({SupabaseService? supabase})
    : _supabase = supabase ?? SupabaseService();

  @override
  Future<SosPublishResult> publish({
    required String activationId,
    required String userCode,
    required int zone,
    required SosCoordinates publicCoordinates,
  }) async {
    try {
      return await _supabase
          .publishSosAlert(
            activationId: activationId,
            userCode: userCode,
            zone: zone,
            latitude: publicCoordinates.latitude,
            longitude: publicCoordinates.longitude,
          )
          .timeout(operationTimeout);
    } catch (error, stackTrace) {
      throw _SosOperationError(
        operation: 'sos_alerts_and_reports.upsert',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> updateLocation({
    required String alertId,
    required String userCode,
    required SosCoordinates publicCoordinates,
  }) async {
    try {
      await _supabase
          .updateActiveSosLocation(
            alertId: alertId,
            userCode: userCode,
            latitude: publicCoordinates.latitude,
            longitude: publicCoordinates.longitude,
          )
          .timeout(operationTimeout);
    } catch (error, stackTrace) {
      throw _SosOperationError(
        operation: 'sos_alerts.update_location',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> finish({
    required String alertId,
    required String userCode,
    String? reportId,
  }) async {
    try {
      await _supabase
          .finishSosAlert(
            alertId: alertId,
            userCode: userCode,
            reportId: reportId,
          )
          .timeout(operationTimeout);
    } catch (error, stackTrace) {
      throw _SosOperationError(
        operation: 'sos_alerts.finish',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

class _SosOperationError implements Exception {
  final String operation;
  final Object cause;
  final StackTrace stackTrace;

  const _SosOperationError({
    required this.operation,
    required this.cause,
    required this.stackTrace,
  });
}

class _SosFailureDetails {
  final SosFailureKind kind;
  final String? operation;
  final String? technicalCode;
  final String technicalMessage;

  const _SosFailureDetails({
    required this.kind,
    required this.technicalMessage,
    this.operation,
    this.technicalCode,
  });
}

/// Owns the 60-second SOS lifecycle. It never requests permissions and never
/// stores an address. Exact coordinates live only in memory while the session
/// is active; the gateway receives an intentionally reduced precision point.
class SosService {
  static const Duration defaultDuration = Duration(seconds: 60);
  static const Duration defaultCancelUnlock = Duration(seconds: 30);
  static const Duration locationUploadThrottle = Duration(seconds: 5);

  static final SosService _instance = SosService._(
    gateway: SupabaseSosGateway(),
    now: DateTime.now,
    duration: defaultDuration,
    cancelUnlock: defaultCancelUnlock,
  );

  factory SosService() => _instance;

  @visibleForTesting
  SosService.forTesting({
    required SosGateway gateway,
    required DateTime Function() now,
    Duration duration = defaultDuration,
    Duration cancelUnlock = defaultCancelUnlock,
    bool startTimer = false,
  }) : this._(
         gateway: gateway,
         now: now,
         duration: duration,
         cancelUnlock: cancelUnlock,
         startTimerAutomatically: startTimer,
       );

  SosService._({
    required this._gateway,
    required this._now,
    required this._duration,
    required this._cancelUnlock,
    this._startTimerAutomatically = true,
  });

  final SosGateway _gateway;
  final DateTime Function() _now;
  final Duration _duration;
  final Duration _cancelUnlock;
  final bool _startTimerAutomatically;

  final ValueNotifier<SosSessionState> state = ValueNotifier<SosSessionState>(
    const SosSessionState.idle(),
  );
  final ValueNotifier<SosCoordinates?> localCoordinates =
      ValueNotifier<SosCoordinates?>(null);

  Timer? _timer;
  String? _userCode;
  int? _zone;
  SosCoordinates? _exactCoordinates;
  SosCoordinates? _lastUploadedCoordinates;
  DateTime? _lastLocationUploadAt;
  bool _transmissionInFlight = false;
  bool _finishInFlight = false;
  int _timerStartCount = 0;
  String? _activationId;

  bool get isActive => state.value.isActive;

  @visibleForTesting
  bool get hasRunningTimer => _timer?.isActive ?? false;

  @visibleForTesting
  int get timerStartCount => _timerStartCount;

  Future<void> activate({
    required String userCode,
    required int zone,
    SosCoordinates? coordinates,
  }) async {
    if (state.value.isActive) return;

    _timer?.cancel();
    _activationId = const Uuid().v4();
    _userCode = userCode;
    _zone = zone;
    _exactCoordinates = coordinates?.isValid == true ? coordinates : null;
    localCoordinates.value = _exactCoordinates;
    _lastUploadedCoordinates = null;
    _lastLocationUploadAt = null;

    final startedAt = _now();
    state.value = SosSessionState(
      phase: SosSessionPhase.activeLocked,
      transmissionStatus: _exactCoordinates == null
          ? SosTransmissionStatus.failed
          : SosTransmissionStatus.sending,
      startedAt: startedAt,
      elapsedSeconds: 0,
      remainingSeconds: _duration.inSeconds,
      message: _exactCoordinates == null
          ? 'S.O.S. activo solo en este dispositivo. Activa la ubicación para enviarlo.'
          : 'Enviando alerta…',
      failureKind: _exactCoordinates == null
          ? SosFailureKind.locationUnavailable
          : SosFailureKind.none,
    );

    if (_startTimerAutomatically) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
      _timerStartCount++;
    }

    if (_exactCoordinates != null) {
      await _transmitInitial();
    }
  }

  /// Recomputes time from the start timestamp so app pauses do not extend an
  /// emergency. Exposed for deterministic unit tests.
  @visibleForTesting
  void tick() {
    final current = state.value;
    final startedAt = current.startedAt;
    if (!current.isActive || startedAt == null) return;

    final elapsed = _now().difference(startedAt);
    final elapsedSeconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
    final remaining = (_duration.inSeconds - elapsedSeconds).clamp(
      0,
      _duration.inSeconds,
    );

    if (remaining == 0) {
      unawaited(finish(automatic: true));
      return;
    }

    final phase = elapsed >= _cancelUnlock
        ? SosSessionPhase.activeCanCancel
        : SosSessionPhase.activeLocked;
    state.value = current.copyWith(
      phase: phase,
      elapsedSeconds: elapsedSeconds,
      remainingSeconds: remaining,
    );
  }

  Future<bool> cancel() async {
    if (!state.value.canCancel) return false;
    await finish();
    return true;
  }

  Future<void> finish({bool automatic = false}) async {
    final current = state.value;
    if (!current.isActive || _finishInFlight) return;

    _finishInFlight = true;
    _timer?.cancel();
    _timer = null;

    final alertId = current.alertId;
    final reportId = current.reportId;
    final userCode = _userCode;

    state.value = current.copyWith(
      phase: SosSessionPhase.finished,
      transmissionStatus: alertId == null
          ? SosTransmissionStatus.idle
          : SosTransmissionStatus.finishing,
      elapsedSeconds: automatic ? _duration.inSeconds : current.elapsedSeconds,
      remainingSeconds: 0,
      message: alertId == null
          ? 'Alerta finalizada. No llegó a transmitirse.'
          : 'Finalizando alerta…',
      clearFailure: true,
    );

    _eraseExactLocation();

    if (alertId == null || userCode == null) {
      _finishInFlight = false;
      return;
    }

    try {
      await _gateway.finish(
        alertId: alertId,
        userCode: userCode,
        reportId: reportId,
      );
      state.value = state.value.copyWith(
        transmissionStatus: SosTransmissionStatus.idle,
        message: 'Alerta finalizada y ubicación retirada.',
        clearLocationIds: true,
        clearFailure: true,
      );
    } catch (error, stackTrace) {
      final failure = _classifyFailure(error);
      _logFailure('finish', failure, stackTrace);
      state.value = state.value.copyWith(
        transmissionStatus: SosTransmissionStatus.failed,
        failureKind: failure.kind,
        message: _messageForFailure(failure.kind, finishing: true),
      );
    } finally {
      _finishInFlight = false;
    }
  }

  Future<void> updateLocation(SosCoordinates coordinates) async {
    if (!state.value.isActive || !coordinates.isValid) return;
    _exactCoordinates = coordinates;
    localCoordinates.value = coordinates;

    if (state.value.alertId == null) {
      await _transmitInitial();
      return;
    }

    final publicCoordinates = coordinates.toPublicApproximation();
    final lastUploadAt = _lastLocationUploadAt;
    if (_lastUploadedCoordinates == publicCoordinates ||
        (lastUploadAt != null &&
            _now().difference(lastUploadAt) < locationUploadThrottle)) {
      return;
    }

    try {
      await _gateway.updateLocation(
        alertId: state.value.alertId!,
        userCode: _userCode!,
        publicCoordinates: publicCoordinates,
      );
      _lastUploadedCoordinates = publicCoordinates;
      _lastLocationUploadAt = _now();
    } catch (error, stackTrace) {
      final failure = _classifyFailure(error);
      _logFailure('update_location', failure, stackTrace);
    }
  }

  Future<void> retry() async {
    final current = state.value;
    if (current.isActive) {
      if (_exactCoordinates == null) return;
      if (current.alertId == null) {
        await _transmitInitial();
      } else {
        await updateLocation(_exactCoordinates!);
      }
      return;
    }

    if (current.phase == SosSessionPhase.finished &&
        current.alertId != null &&
        _userCode != null) {
      await _retryFinish();
    }
  }

  Future<void> _transmitInitial() async {
    if (_transmissionInFlight || !state.value.isActive) return;
    final coordinates = _exactCoordinates;
    final activationId = _activationId;
    final userCode = _userCode;
    final zone = _zone;
    if (coordinates == null ||
        activationId == null ||
        userCode == null ||
        zone == null) {
      return;
    }

    _transmissionInFlight = true;
    state.value = state.value.copyWith(
      transmissionStatus: SosTransmissionStatus.sending,
      message: 'Enviando alerta…',
      clearFailure: true,
    );
    final publicCoordinates = coordinates.toPublicApproximation();

    try {
      final result = await _gateway.publish(
        activationId: activationId,
        userCode: userCode,
        zone: zone,
        publicCoordinates: publicCoordinates,
      );
      if (!state.value.isActive) {
        await _gateway.finish(
          alertId: result.alertId,
          userCode: userCode,
          reportId: result.reportId,
        );
        return;
      }
      _lastUploadedCoordinates = publicCoordinates;
      _lastLocationUploadAt = _now();
      state.value = state.value.copyWith(
        transmissionStatus: SosTransmissionStatus.sent,
        alertId: result.alertId,
        reportId: result.reportId,
        message: 'Alerta S.O.S. compartida con usuarios conectados.',
        clearFailure: true,
      );
    } catch (error, stackTrace) {
      final failure = _classifyFailure(error);
      _logFailure('publish', failure, stackTrace);
      if (state.value.isActive) {
        state.value = state.value.copyWith(
          transmissionStatus: SosTransmissionStatus.failed,
          failureKind: failure.kind,
          message: _messageForFailure(failure.kind),
        );
      }
    } finally {
      _transmissionInFlight = false;
    }
  }

  Future<void> _retryFinish() async {
    if (_finishInFlight) return;
    _finishInFlight = true;
    state.value = state.value.copyWith(
      transmissionStatus: SosTransmissionStatus.finishing,
      message: 'Reintentando cierre…',
      clearFailure: true,
    );
    try {
      await _gateway.finish(
        alertId: state.value.alertId!,
        userCode: _userCode!,
        reportId: state.value.reportId,
      );
      state.value = state.value.copyWith(
        transmissionStatus: SosTransmissionStatus.idle,
        message: 'Alerta finalizada y ubicación retirada.',
        clearLocationIds: true,
        clearFailure: true,
      );
    } catch (error, stackTrace) {
      final failure = _classifyFailure(error);
      _logFailure('retry_finish', failure, stackTrace);
      state.value = state.value.copyWith(
        transmissionStatus: SosTransmissionStatus.failed,
        failureKind: failure.kind,
        message: _messageForFailure(failure.kind, finishing: true),
      );
    } finally {
      _finishInFlight = false;
    }
  }

  void reset() {
    if (state.value.isActive) return;
    _timer?.cancel();
    _timer = null;
    _userCode = null;
    _zone = null;
    _activationId = null;
    _eraseExactLocation();
    state.value = const SosSessionState.idle();
  }

  void _eraseExactLocation() {
    _exactCoordinates = null;
    localCoordinates.value = null;
    _lastUploadedCoordinates = null;
    _lastLocationUploadAt = null;
  }

  _SosFailureDetails _classifyFailure(Object error) {
    if (error is _SosOperationError) {
      final failure = _classifyFailure(error.cause);
      return _SosFailureDetails(
        kind: failure.kind,
        operation: error.operation,
        technicalCode: failure.technicalCode,
        technicalMessage: failure.technicalMessage,
      );
    }

    if (error is SosGatewayException) {
      return _SosFailureDetails(
        kind: error.kind,
        technicalCode: error.technicalCode,
        technicalMessage: error.technicalMessage,
      );
    }

    if (error is TimeoutException) {
      return _SosFailureDetails(
        kind: SosFailureKind.timeout,
        technicalMessage: error.message ?? 'Operation timed out',
      );
    }

    if (error is PostgrestException) {
      final code = error.code?.toUpperCase();
      final message = error.message.toLowerCase();
      final kind = switch (code) {
        '401' ||
        '403' ||
        '42501' ||
        'PGRST301' ||
        'PGRST302' => SosFailureKind.authentication,
        '408' || '504' => SosFailureKind.timeout,
        '42P01' || '42703' || 'PGRST204' || 'PGRST205' => SosFailureKind.schema,
        '500' ||
        '502' ||
        '503' ||
        'PGRST000' ||
        'PGRST001' ||
        'PGRST002' => SosFailureKind.backendUnavailable,
        _
            when message.contains('row-level security') ||
                message.contains('permission denied') ||
                message.contains('not authorized') =>
          SosFailureKind.authentication,
        _ => SosFailureKind.rejected,
      };
      return _SosFailureDetails(
        kind: kind,
        technicalCode: error.code,
        technicalMessage: error.message,
      );
    }

    if (error is AuthRetryableFetchException) {
      return _SosFailureDetails(
        kind: SosFailureKind.backendUnavailable,
        technicalCode: error.statusCode,
        technicalMessage: error.message,
      );
    }

    if (error is AuthException) {
      return _SosFailureDetails(
        kind: SosFailureKind.authentication,
        technicalCode: error.code ?? error.statusCode,
        technicalMessage: error.message,
      );
    }

    if (error is http.ClientException) {
      final message = error.message.toLowerCase();
      final isExplicitlyOffline =
          message.contains('network is unreachable') ||
          message.contains('failed host lookup') ||
          message.contains('no internet') ||
          message.contains('internet disconnected') ||
          message.contains('network connection was lost');
      return _SosFailureDetails(
        kind: isExplicitlyOffline
            ? SosFailureKind.offline
            : SosFailureKind.backendUnavailable,
        technicalMessage: error.message,
      );
    }

    return _SosFailureDetails(
      kind: SosFailureKind.unknown,
      technicalMessage: error.toString(),
    );
  }

  String _messageForFailure(SosFailureKind kind, {bool finishing = false}) {
    if (finishing) {
      return switch (kind) {
        SosFailureKind.offline =>
          'Sin conexión. El cierre queda pendiente para reintentar.',
        SosFailureKind.authentication =>
          'No pudimos autorizar el cierre. Revisa tu sesión y reintenta.',
        SosFailureKind.timeout =>
          'El servidor tardó demasiado en cerrar la alerta. Reintentaremos.',
        SosFailureKind.schema =>
          'El servidor necesita una actualización para cerrar la alerta.',
        _ => 'No pudimos cerrar la alerta en el servidor. Reintentaremos.',
      };
    }

    return switch (kind) {
      SosFailureKind.offline =>
        'Sin conexión. El S.O.S. está activo solo en este dispositivo.',
      SosFailureKind.backendUnavailable =>
        'No pudimos conectar con el servicio de alertas. Reintentaremos.',
      SosFailureKind.rejected =>
        'Supabase rechazó la alerta. Revisa los datos de tu perfil y reintenta.',
      SosFailureKind.authentication =>
        'No pudimos autorizar el envío. Revisa tu sesión y reintenta.',
      SosFailureKind.timeout =>
        'El servidor tardó demasiado. El S.O.S. sigue activo y reintentaremos.',
      SosFailureKind.schema =>
        'El servidor S.O.S. necesita una actualización. Reintentaremos.',
      SosFailureKind.locationUnavailable =>
        'S.O.S. activo solo en este dispositivo. Activa la ubicación para enviarlo.',
      SosFailureKind.none ||
      SosFailureKind.unknown => 'No pudimos enviar la alerta. Reintentaremos.',
    };
  }

  void _logFailure(
    String operation,
    _SosFailureDetails failure,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    final sanitized = failure.technicalMessage
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._-]+'), 'Bearer [REDACTED]')
        .replaceAll(
          RegExp(r'[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'),
          '[REDACTED_TOKEN]',
        )
        .replaceAll(RegExp(r'apikey=[^&\s]+'), 'apikey=[REDACTED]');
    debugPrint(
      '[SOS][${failure.operation ?? operation}] kind=${failure.kind.name} '
      'code=${failure.technicalCode ?? 'none'} error=$sanitized',
    );
    debugPrintStack(
      label: '[SOS][${failure.operation ?? operation}] stack',
      stackTrace: stackTrace,
    );
  }

  @visibleForTesting
  void dispose() {
    _timer?.cancel();
    state.dispose();
    localCoordinates.dispose();
  }
}
