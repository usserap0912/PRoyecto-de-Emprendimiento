import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/sos_session.dart';
import 'package:safezone/screens/sos/sos_screen.dart';
import 'package:safezone/services/sos_service.dart';

class _UiSosGateway implements SosGateway {
  int publishCalls = 0;
  int finishCalls = 0;

  @override
  Future<SosPublishResult> publish({
    required String activationId,
    required String userCode,
    required int zone,
    required SosCoordinates publicCoordinates,
  }) async {
    publishCalls++;
    return const SosPublishResult(alertId: 'alert-ui');
  }

  @override
  Future<void> updateLocation({
    required String alertId,
    required String userCode,
    required SosCoordinates publicCoordinates,
  }) async {}

  @override
  Future<void> finish({
    required String alertId,
    required String userCode,
    String? reportId,
  }) async {
    finishCalls++;
  }
}

void main() {
  testWidgets('SosScreen creates and disposes both tickers without exception', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: SosScreen(userCode: 'VEC-001', zone: 4)),
    );
    expect(find.text('¿Estás en peligro?'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('counter starts at 60 and SosScreen receives every second', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _UiSosGateway();
    final service = SosService.forTesting(
      gateway: gateway,
      now: tester.binding.clock.now,
      startTimer: true,
    );
    var notifications = 0;
    service.state.addListener(() => notifications++);

    await tester.pumpWidget(
      MaterialApp(
        home: SosScreen(userCode: 'VEC-001', zone: 4, service: service),
      ),
    );
    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    await tester.pump();

    expect(find.text('60'), findsOneWidget);
    expect(gateway.publishCalls, 1);
    final afterActivation = notifications;

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('59'), findsOneWidget);
    expect(notifications, greaterThan(afterActivation));
    final afterFirstSecond = notifications;

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('58'), findsOneWidget);
    expect(notifications, greaterThan(afterFirstSecond));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    service.dispose();
  });

  testWidgets('rebuilding or navigating does not restart the SOS timer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _UiSosGateway();
    final service = SosService.forTesting(
      gateway: gateway,
      now: tester.binding.clock.now,
      startTimer: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SosScreen(userCode: 'VEC-001', zone: 4, service: service),
      ),
    );
    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('50'), findsOneWidget);
    expect(service.timerStartCount, 1);

    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.92, longitude: -77.02),
    );
    expect(service.timerStartCount, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpWidget(
      MaterialApp(
        home: SosScreen(userCode: 'VEC-001', zone: 4, service: service),
      ),
    );
    await tester.pump();

    expect(find.text('42'), findsOneWidget);
    expect(service.timerStartCount, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    service.dispose();
  });

  testWidgets('one timer finalizes once at 60 seconds', (tester) async {
    final gateway = _UiSosGateway();
    final service = SosService.forTesting(
      gateway: gateway,
      now: tester.binding.clock.now,
      startTimer: true,
    );
    addTearDown(service.dispose);

    await service.activate(
      userCode: 'VEC-001',
      zone: 4,
      coordinates: const SosCoordinates(latitude: -11.91, longitude: -77.01),
    );
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();

    expect(service.state.value.phase, SosSessionPhase.finished);
    expect(service.state.value.remainingSeconds, 0);
    expect(service.hasRunningTimer, isFalse);
    expect(gateway.finishCalls, 1);
    expect(service.localCoordinates.value, isNull);

    await tester.pump(const Duration(seconds: 3));
    expect(gateway.finishCalls, 1);
  });

  test('Web-facing SOS files do not import dart:io or call looping audio', () {
    const paths = <String>[
      'lib/screens/sos/sos_screen.dart',
      'lib/services/sos_service.dart',
      'lib/services/sos_realtime_service.dart',
      'lib/services/supabase_service.dart',
      'lib/services/report_service.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains("import 'dart:io'")), reason: path);
      if (path.endsWith('sos_screen.dart')) {
        expect(source, isNot(contains('playLoopingSosAlarm')), reason: path);
      }
    }
  });

  test('SosScreen uses the correct ticker mixin for two controllers', () {
    final source = File('lib/screens/sos/sos_screen.dart').readAsStringSync();
    expect(source, contains('with TickerProviderStateMixin'));
    expect(RegExp(r'AnimationController\(').allMatches(source).length, 2);
    expect(
      RegExp(r'\.dispose\(\);').allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
  });
}
