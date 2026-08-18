enum SosSessionPhase { idle, activeLocked, activeCanCancel, finished }

enum SosTransmissionStatus { idle, sending, sent, failed, finishing }

/// Describes why a backend operation failed without conflating every failure
/// with a missing Internet connection.
enum SosFailureKind {
  none,
  offline,
  backendUnavailable,
  rejected,
  authentication,
  timeout,
  schema,
  locationUnavailable,
  unknown,
}

/// A typed gateway error. Production adapters and tests can use it when the
/// failure category is already known before it reaches [SosService].
class SosGatewayException implements Exception {
  final SosFailureKind kind;
  final String operation;
  final String? technicalCode;
  final String technicalMessage;

  const SosGatewayException({
    required this.kind,
    required this.operation,
    required this.technicalMessage,
    this.technicalCode,
  });

  @override
  String toString() =>
      'SosGatewayException(kind: ${kind.name}, operation: $operation, '
      'code: $technicalCode, message: $technicalMessage)';
}

class SosCoordinates {
  final double latitude;
  final double longitude;

  const SosCoordinates({required this.latitude, required this.longitude});

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Public SOS coordinates are deliberately reduced to roughly street-level
  /// precision. The exact device position remains local to the active session.
  SosCoordinates toPublicApproximation() => SosCoordinates(
    latitude: double.parse(latitude.toStringAsFixed(4)),
    longitude: double.parse(longitude.toStringAsFixed(4)),
  );

  @override
  bool operator ==(Object other) =>
      other is SosCoordinates &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

class SosPublishResult {
  final String alertId;
  final String? reportId;

  const SosPublishResult({required this.alertId, this.reportId});
}

class SosSessionState {
  final SosSessionPhase phase;
  final SosTransmissionStatus transmissionStatus;
  final DateTime? startedAt;
  final int elapsedSeconds;
  final int remainingSeconds;
  final String? alertId;
  final String? reportId;
  final String? message;
  final SosFailureKind failureKind;

  const SosSessionState({
    required this.phase,
    required this.transmissionStatus,
    this.startedAt,
    this.elapsedSeconds = 0,
    this.remainingSeconds = 60,
    this.alertId,
    this.reportId,
    this.message,
    this.failureKind = SosFailureKind.none,
  });

  const SosSessionState.idle()
    : this(
        phase: SosSessionPhase.idle,
        transmissionStatus: SosTransmissionStatus.idle,
      );

  bool get isActive =>
      phase == SosSessionPhase.activeLocked ||
      phase == SosSessionPhase.activeCanCancel;

  bool get canCancel => phase == SosSessionPhase.activeCanCancel;

  bool get wasSent => transmissionStatus == SosTransmissionStatus.sent;

  SosSessionState copyWith({
    SosSessionPhase? phase,
    SosTransmissionStatus? transmissionStatus,
    DateTime? startedAt,
    int? elapsedSeconds,
    int? remainingSeconds,
    String? alertId,
    String? reportId,
    String? message,
    SosFailureKind? failureKind,
    bool clearLocationIds = false,
    bool clearMessage = false,
    bool clearFailure = false,
  }) {
    return SosSessionState(
      phase: phase ?? this.phase,
      transmissionStatus: transmissionStatus ?? this.transmissionStatus,
      startedAt: startedAt ?? this.startedAt,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      alertId: clearLocationIds ? null : alertId ?? this.alertId,
      reportId: clearLocationIds ? null : reportId ?? this.reportId,
      message: clearMessage ? null : message ?? this.message,
      failureKind: clearFailure
          ? SosFailureKind.none
          : failureKind ?? this.failureKind,
    );
  }
}
