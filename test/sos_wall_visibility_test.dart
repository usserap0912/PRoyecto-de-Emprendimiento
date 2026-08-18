import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/models/wall_time_filter.dart';
import 'package:safezone/services/report_service.dart';
import 'dart:io';

Report _report({
  required DateTime createdAt,
  String category = 'sos',
  String status = 'activo',
}) {
  return Report(
    id: 'report-1',
    userCode: 'VEC-001',
    zone: 4,
    category: category,
    description: 'Alerta',
    tag: 'rojo',
    status: status,
    createdAt: createdAt,
  );
}

void main() {
  test('legacy SOS projection is visible to another user in the same zone', () {
    final report = Report.fromMap({
      'id': '5ce2c262-3054-4fc6-a9d8-995096276128',
      'user_code': 'User-A1B2',
      'zone': 4,
      'category': 'sos',
      'description': 'Alerta S.O.S. activa.',
      'tag': 'rojo',
      'status': 'activo',
      'created_at': '2026-08-18T12:00:00.000Z',
    });
    const receivingUserCode = 'User-B3C4';

    expect(report.userCode, isNot(receivingUserCode));
    expect(report.zone, 4);
    expect(
      ReportService.isVisibleInWall(
        report,
        now: DateTime.utc(2026, 8, 18, 12, 1),
      ),
      isTrue,
    );
  });

  test('wall projection failure is not swallowed as successful sharing', () {
    final source = File(
      'lib/services/supabase_service.dart',
    ).readAsStringSync();

    expect(source, contains('Error.throwWithStackTrace(error, stackTrace)'));
    expect(source, contains("'status': 'cancelado'"));
    expect(source, isNot(contains('optional wall projection')));
  });

  test('active SOS follows the selected wall window', () {
    final now = DateTime.utc(2026, 8, 17, 12);
    expect(
      ReportService.isVisibleInWall(
        _report(createdAt: now.subtract(const Duration(hours: 5))),
        filter: WallTimeFilter.last6Hours,
        now: now,
      ),
      isTrue,
    );
    expect(
      ReportService.isVisibleInWall(
        _report(createdAt: now.subtract(const Duration(hours: 7))),
        filter: WallTimeFilter.last6Hours,
        now: now,
      ),
      isFalse,
    );
  });

  test('finished SOS and normal reports use the same selected window', () {
    final now = DateTime.utc(2026, 8, 17, 12);
    expect(
      ReportService.isVisibleInWall(
        _report(
          createdAt: now.subtract(const Duration(minutes: 4)),
          status: 'resuelto',
        ),
        filter: WallTimeFilter.last6Hours,
        now: now,
      ),
      isTrue,
    );
    expect(
      ReportService.isVisibleInWall(
        _report(
          createdAt: now.subtract(const Duration(hours: 7)),
          status: 'resuelto',
        ),
        filter: WallTimeFilter.last6Hours,
        now: now,
      ),
      isFalse,
    );
    expect(
      ReportService.isVisibleInWall(
        _report(
          createdAt: now.subtract(const Duration(days: 2)),
          category: 'robo',
        ),
        filter: WallTimeFilter.last7Days,
        now: now,
      ),
      isTrue,
    );
  });
}
