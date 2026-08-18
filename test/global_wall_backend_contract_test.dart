import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active wall loads globally before subscribing to realtime', () {
    final source = File('lib/screens/wall/wall_screen.dart').readAsStringSync();

    expect(source, isNot(contains('zone: widget.zone')));
    final initialLoad = source.indexOf('await _loadReports();');
    final realtimeStart = source.indexOf('if (mounted) _subscribeToRealtime();');
    expect(initialLoad, greaterThanOrEqualTo(0));
    expect(realtimeStart, greaterThan(initialLoad));
    expect(source, contains('[WALL][initial] count='));
    expect(source, contains('[WALL][merged] count='));
  });

  test('legacy backend migration guarantees persistence and realtime', () {
    final sql = File(
      'supabase/migrations/global_wall_realtime_legacy.sql',
    ).readAsStringSync();

    expect(sql, contains('UNIQUE (report_id, user_code)'));
    expect(sql, contains('ADD TABLE public.reports'));
    expect(sql, contains('ADD TABLE public.sos_alerts'));
    expect(sql, contains('ADD TABLE public.reactions'));
    expect(sql, contains('ADD TABLE public.report_comments'));
    expect(sql, contains('archived_report_comments'));
    expect(sql, isNot(contains('auth.uid')));
    expect(sql, isNot(contains('auth_user_id')));
  });
}
