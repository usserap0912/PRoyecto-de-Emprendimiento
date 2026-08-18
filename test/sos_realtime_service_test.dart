import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/services/sos_realtime_service.dart';

Map<String, dynamic> _row({
  required String id,
  required String userCode,
  required DateTime createdAt,
  Object? latitude = -11.9131,
  Object? longitude = -77.0162,
  String status = 'activo',
}) {
  return <String, dynamic>{
    'id': id,
    'user_code': userCode,
    'latitude': latitude,
    'longitude': longitude,
    'status': status,
    'created_at': createdAt.toIso8601String(),
  };
}

void main() {
  final service = SosRealtimeService();

  setUp(service.resetForTesting);
  tearDown(service.resetForTesting);

  test('only fresh active alerts from other users become public markers', () {
    final now = DateTime.utc(2026, 8, 17, 12);

    final alerts = service.parseVisibleAlerts(
      [
        _row(id: 'fresh', userCode: 'VEC-002', createdAt: now),
        _row(id: 'own', userCode: 'VEC-001', createdAt: now),
        _row(
          id: 'stale',
          userCode: 'VEC-003',
          createdAt: now.subtract(const Duration(seconds: 76)),
        ),
        _row(
          id: 'finished',
          userCode: 'VEC-004',
          createdAt: now,
          status: 'atendido',
        ),
        _row(
          id: 'no-location',
          userCode: 'VEC-005',
          createdAt: now,
          latitude: null,
          longitude: null,
        ),
      ],
      currentUserCode: 'VEC-001',
      now: now,
    );

    expect(alerts.map((alert) => alert.id), ['fresh']);
    expect(alerts.single.address, isNull);
  });

  test('remote SOS notification is emitted once per alert id', () {
    final now = DateTime.utc(2026, 8, 17, 12);
    final firstRows = [
      _row(id: 'alert-1', userCode: 'VEC-002', createdAt: now),
    ];

    expect(
      service
          .processSnapshotForTesting(
            firstRows,
            currentUserCode: 'VEC-001',
            now: now,
          )
          ?.id,
      'alert-1',
    );
    expect(
      service.processSnapshotForTesting(
        firstRows,
        currentUserCode: 'VEC-001',
        now: now,
      ),
      isNull,
      reason: 'A duplicate snapshot must not reproduce the sound.',
    );

    final secondRows = [
      _row(id: 'alert-2', userCode: 'VEC-003', createdAt: now),
      ...firstRows,
    ];
    expect(
      service
          .processSnapshotForTesting(
            secondRows,
            currentUserCode: 'VEC-001',
            now: now,
          )
          ?.id,
      'alert-2',
      reason: 'A genuinely new alert must notify again.',
    );
  });

  test('reconnect keeps notification history for the same user', () {
    final now = DateTime.utc(2026, 8, 17, 12);
    final rows = [_row(id: 'alert-1', userCode: 'VEC-002', createdAt: now)];

    expect(
      service.processSnapshotForTesting(
        rows,
        currentUserCode: 'VEC-001',
        now: now,
      ),
      isNotNull,
    );
    service.stop(clearState: true);
    expect(
      service.processSnapshotForTesting(
        rows,
        currentUserCode: 'VEC-001',
        now: now,
      ),
      isNull,
    );
  });

  test('creator never receives the remote SOS notification', () {
    final now = DateTime.utc(2026, 8, 17, 12);

    expect(
      service.processSnapshotForTesting(
        [_row(id: 'own-alert', userCode: 'VEC-001', createdAt: now)],
        currentUserCode: 'VEC-001',
        now: now,
      ),
      isNull,
    );
    expect(service.activeAlerts.value, isEmpty);
  });
}
