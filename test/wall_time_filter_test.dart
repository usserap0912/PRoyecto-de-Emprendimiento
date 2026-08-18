import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/models/wall_time_filter.dart';
import 'package:safezone/services/report_service.dart';

Report _report(String id, DateTime createdAt, {String category = 'robo'}) {
  return Report(
    id: id,
    userCode: 'VEC-$id',
    zone: 4,
    category: category,
    description: 'Alerta $id',
    tag: 'rojo',
    createdAt: createdAt,
  );
}

void main() {
  final now = DateTime.utc(2026, 8, 17, 12);

  test('filters use exact rolling windows of 6h, 24h, 48h and 7d', () {
    expect(WallTimeFilter.last6Hours.duration, const Duration(hours: 6));
    expect(WallTimeFilter.last24Hours.duration, const Duration(hours: 24));
    expect(WallTimeFilter.last48Hours.duration, const Duration(hours: 48));
    expect(WallTimeFilter.last7Days.duration, const Duration(days: 7));

    for (final filter in WallTimeFilter.values) {
      expect(filter.includes(now.subtract(filter.duration), now: now), isTrue);
      expect(
        filter.includes(
          now.subtract(filter.duration).subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isFalse,
      );
    }
  });

  test('filter result is newest-first and count matches the active window', () {
    final reports = <Report>[
      _report('old', now.subtract(const Duration(hours: 8))),
      _report('new', now.subtract(const Duration(minutes: 2))),
      _report('middle', now.subtract(const Duration(hours: 3))),
    ];

    final visible = WallTimeFilter.last6Hours.filterAndSort(reports, now: now);

    expect(visible.map((report) => report.id), <String>['new', 'middle']);
    expect(visible.length, 2);
    expect(wallResultLabel(visible.length), '2 alertas');
    expect(wallResultLabel(1), '1 alerta');
  });

  test('next expiration schedules automatic wall removal', () {
    final reports = <Report>[
      _report('later', now.subtract(const Duration(hours: 1))),
      _report('next', now.subtract(const Duration(hours: 5))),
    ];

    expect(
      WallTimeFilter.last6Hours.nextExpirationDelay(reports, now: now),
      const Duration(hours: 1),
    );
  });

  test('filtering the wall never removes historical source data', () {
    final reports = <Report>[
      _report('visible', now.subtract(const Duration(hours: 1))),
      _report('historical', now.subtract(const Duration(days: 30))),
    ];

    final visible = WallTimeFilter.last7Days.filterAndSort(reports, now: now);

    expect(visible.map((report) => report.id), <String>['visible']);
    expect(reports.map((report) => report.id), <String>[
      'visible',
      'historical',
    ]);
  });

  test('SOS active and finished obey the same window', () {
    final active = _report(
      'active-sos',
      now.subtract(const Duration(hours: 5)),
      category: 'sos',
    );
    final finished = _report(
      'finished-sos',
      now.subtract(const Duration(hours: 7)),
      category: 'sos',
    );

    expect(
      WallTimeFilter.last6Hours.includes(active.createdAt, now: now),
      true,
    );
    expect(
      WallTimeFilter.last6Hours.includes(finished.createdAt, now: now),
      false,
    );
  });

  test('initial Supabase load is not erased by an empty realtime snapshot', () {
    final persisted = _report(
      'persisted',
      now.subtract(const Duration(hours: 1)),
    );

    final merged = ReportService.mergeWallSnapshots(
      [persisted],
      const [],
      filter: WallTimeFilter.last6Hours,
      now: now,
    );

    expect(merged.map((report) => report.id), ['persisted']);
  });
}
