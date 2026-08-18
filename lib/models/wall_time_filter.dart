import 'package:safezone/models/report.dart';

String wallResultLabel(int count) => '$count alerta${count == 1 ? '' : 's'}';

enum WallTimeFilter {
  last6Hours(label: 'Últimas horas', duration: Duration(hours: 6)),
  last24Hours(label: 'Hace 1 día', duration: Duration(hours: 24)),
  last48Hours(label: 'Hace 2 días', duration: Duration(hours: 48)),
  last7Days(label: 'Esta semana', duration: Duration(days: 7));

  const WallTimeFilter({required this.label, required this.duration});

  final String label;
  final Duration duration;

  DateTime cutoff(DateTime now) => now.toUtc().subtract(duration);

  bool includes(DateTime createdAt, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    return !createdAt.toUtc().isBefore(cutoff(reference));
  }

  List<Report> filterAndSort(Iterable<Report> reports, {DateTime? now}) {
    final visible = reports
        .where((report) => includes(report.createdAt, now: now))
        .toList();
    visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return visible;
  }

  Duration? nextExpirationDelay(Iterable<Report> reports, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    final expirations =
        reports
            .map((report) => report.createdAt.toUtc().add(duration))
            .where((expiration) => expiration.isAfter(reference))
            .toList()
          ..sort();
    return expirations.isEmpty ? null : expirations.first.difference(reference);
  }
}
