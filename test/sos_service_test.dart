import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:safezone/models/sos_session.dart';
import 'package:safezone/services/sos_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSosGateway implements SosGateway {
  Object? publishError;
  Object? finishError;
  int publishCalls = 0;
  int updateCalls = 0;
  int finishCalls = 0;
  SosCoordinates? publishedCoordinates;
  final List<String> activationIds = [];

  @override
  Future<SosPublishResult> publish({
    required String activationId,
    required String userCode,
    required int zone,
    required SosCoordinates publicCoordinates,
  }) async {
    publishCalls++;
    activationIds.add(activationId);
    if (publishError case final error?) throw error;
    publishedCoordinates = publicCoordinates;
    return const SosPublishResult(alertId: 'alert-1', reportId: 'report-1');
  }

  @override
  Future<void> updateLocation({
    required String alertId,
    required String userCode,
    required SosCoordinates publicCoordinates,
  }) async {
    updateCalls++;
  }

  @override
  Future<void> finish({
    required String alertId,
    required String userCode,
    String? reportId,
  }) async {
    finishCalls++;
    if (finishError case final error?) throw error;
  }
}

void main() {
  late DateTime now;
  late _FakeSosGateway gateway;
  late SosService service;

  setUp(() {
    now = DateTime.utc(2026, 8, 17, 12);
    gateway = _FakeSosGateway();
    service = SosService.forTesting(gateway: gateway, now: () => now);
  });

  tearDown(() => service.dispose());

  test(
    'activation enters the locked state and confirms backend success',
    () async {
      await service.activate(
        userCode: 'VEC-001',
        zone: 4,
        coordinates: const SosCoordinates(
          latitude: -11.91308041,
          longitude: -77.01619971,
        ),
      );

      expect(service.state.value.phase, SosSessionPhase.activeLocked);
      expect(
        service.state.value.transmissionStatus,
        SosTransmissionStatus.sent,
      );
      expect(service.localCoordinates.value, isNotNull);
      expect(gateway.publishCalls, 1);
      expect(
        gateway.publishedCoordinates,
        const SosCoordinates(latitude: -11.9131, longitude: -77.0162),
      );
    },
  );

  test('retry reuses one idempotent activation id', () async {
    gateway.publishError = const SosGatewayException(
      kind: SosFailureKind.backendUnavailable,
      operation: 'reports.upsert',
      technicalMessage: 'service unavailable',
    );
    await service.activate(
      userCode: 'User-A1B2',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );

    gateway.publishError = null;
    await service.retry();

    expect(gateway.publishCalls, 2);
    expect(gateway.activationIds.toSet(), hasLength(1));
    expect(service.state.value.transmissionStatus, SosTransmissionStatus.sent);
  });

  test(
    'cancellation stays locked before 30 seconds and unlocks at 30',
    () async {
      await service.activate(userCode: 'VEC-001', zone: 4);

      now = now.add(const Duration(seconds: 29));
      service.tick();
      expect(service.state.value.phase, SosSessionPhase.activeLocked);
      expect(await service.cancel(), isFalse);

      now = now.add(const Duration(seconds: 1));
      service.tick();
      expect(service.state.value.phase, SosSessionPhase.activeCanCancel);
    },
  );

  test('manual cancellation finishes the transmitted alert', () async {
    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    now = now.add(const Duration(seconds: 30));
    service.tick();

    expect(await service.cancel(), isTrue);
    expect(service.state.value.phase, SosSessionPhase.finished);
    expect(gateway.finishCalls, 1);
    expect(service.state.value.alertId, isNull);
    expect(service.localCoordinates.value, isNull);
  });

  test('alert auto-finishes at 60 seconds', () async {
    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    now = now.add(const Duration(seconds: 60));

    service.tick();
    await Future<void>.delayed(Duration.zero);

    expect(service.state.value.phase, SosSessionPhase.finished);
    expect(service.state.value.remainingSeconds, 0);
    expect(gateway.finishCalls, 1);
  });

  test(
    'real offline activation remains active locally and can retry',
    () async {
      gateway.publishError = const SosGatewayException(
        kind: SosFailureKind.offline,
        operation: 'sos_alerts.insert',
        technicalMessage: 'network is unreachable',
      );
      await service.activate(
        userCode: 'VEC-001',
        zone: 4,
        coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
      );

      expect(service.isActive, isTrue);
      expect(
        service.state.value.transmissionStatus,
        SosTransmissionStatus.failed,
      );
      expect(service.state.value.failureKind, SosFailureKind.offline);
      expect(service.state.value.message, startsWith('Sin conexión.'));

      gateway.publishError = null;
      await service.retry();
      expect(
        service.state.value.transmissionStatus,
        SosTransmissionStatus.sent,
      );
      expect(service.state.value.failureKind, SosFailureKind.none);
      expect(gateway.publishCalls, 2);
    },
  );

  test('Supabase rejection is never labeled as no Internet', () async {
    gateway.publishError = const PostgrestException(
      message: 'violates foreign key constraint',
      code: '23503',
    );

    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );

    expect(service.state.value.failureKind, SosFailureKind.rejected);
    expect(service.state.value.message, contains('Supabase rechazó'));
    expect(service.state.value.message, isNot(contains('Sin conexión')));
  });

  test(
    'ambiguous web fetch failure is backend unavailable, not offline',
    () async {
      gateway.publishError = http.ClientException('Failed to fetch');

      await service.activate(
        userCode: 'VEC-001',
        zone: 4,
        coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
      );

      expect(
        service.state.value.failureKind,
        SosFailureKind.backendUnavailable,
      );
      expect(service.state.value.message, contains('servicio de alertas'));
      expect(service.state.value.message, isNot(contains('Sin conexión')));
    },
  );

  test('authentication and timeout keep distinct failure states', () async {
    gateway.publishError = const PostgrestException(
      message: 'new row violates row-level security policy',
      code: '42501',
    );
    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    expect(service.state.value.failureKind, SosFailureKind.authentication);

    service.dispose();
    gateway = _FakeSosGateway()..publishError = TimeoutException('timeout');
    service = SosService.forTesting(gateway: gateway, now: () => now);
    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    expect(service.state.value.failureKind, SosFailureKind.timeout);
  });

  test('finishing stops timer and rejects later location uploads', () async {
    service.dispose();
    service = SosService.forTesting(
      gateway: gateway,
      now: () => now,
      startTimer: true,
    );
    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    expect(service.hasRunningTimer, isTrue);

    now = now.add(const Duration(seconds: 30));
    service.tick();
    await service.cancel();
    expect(service.hasRunningTimer, isFalse);

    await service.updateLocation(
      const SosCoordinates(latitude: -11.92, longitude: -77.02),
    );
    expect(gateway.updateCalls, 0);
  });

  test('backend finish failure is explicit and retryable', () async {
    gateway.finishError = const SosGatewayException(
      kind: SosFailureKind.backendUnavailable,
      operation: 'sos_alerts.finish',
      technicalMessage: 'service unavailable',
    );
    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    now = now.add(const Duration(seconds: 30));
    service.tick();
    await service.cancel();

    expect(service.state.value.phase, SosSessionPhase.finished);
    expect(
      service.state.value.transmissionStatus,
      SosTransmissionStatus.failed,
    );
    expect(service.state.value.message, contains('cerrar'));

    gateway.finishError = null;
    await service.retry();
    expect(service.state.value.transmissionStatus, SosTransmissionStatus.idle);
    expect(gateway.finishCalls, 2);
  });

  test('active legacy SOS write includes the visible user code', () {
    final source = File(
      'lib/services/supabase_service.dart',
    ).readAsStringSync();

    expect(source, contains("'user_code': userCode"));
    expect(source, contains("'id': activationId"));
    expect(source, contains('.from(reportsTable)'));
    expect(source, isNot(contains('auth_user_id')));
  });
}
