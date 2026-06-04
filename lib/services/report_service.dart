import 'package:safezone/models/report.dart';
import 'package:safezone/services/supabase_service.dart';

class ReportService {
  final SupabaseService _supabase = SupabaseService();

  /// Obtiene todos los reportes activos
  Future<List<Report>> getReports({String? zone}) async {
    try {
      var query = _supabase.client
          .from(_supabase.reportsTable)
          .select();

      if (zone != null) {
        query = query.eq('zone', zone);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List)
          .map((item) => Report.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Si no hay conexión a Supabase, devolvemos datos de ejemplo
      return _getSampleReports();
    }
  }

  /// Crea un nuevo reporte
  Future<void> createReport(Report report) async {
    try {
      await _supabase.client.from(_supabase.reportsTable).insert(report.toMap());
    } catch (e) {
      // Fallback: no hacer nada, en modo offline se perdería
    }
  }

  /// Actualiza el estado de un reporte
  Future<void> updateReportStatus(String reportId, String status) async {
    try {
      await _supabase.client
          .from(_supabase.reportsTable)
          .update({'status': status})
          .eq('id', reportId);
    } catch (e) {
      // Fallback offline
    }
  }

  /// Reacciona a un reporte
  Future<void> reactToReport(String reportId, String reactionType) async {
    try {
      await _supabase.client.from(_supabase.reactionsTable).insert({
        'report_id': reportId,
        'reaction_type': reactionType,
      });
    } catch (e) {
      // Fallback offline
    }
  }

  /// Devuelve datos de ejemplo cuando no hay conexión
  List<Report> _getSampleReports() {
    return [
      Report(
        id: 'sample-1',
        userCode: 'User-A7K3',
        zone: 3,
        category: 'robo',
        description:
            'Moto lineal negra sospechosa dando vueltas en la Av. Revolución desde las 10 pm. Tiene dos ocupantes sin casco.',
        tag: 'rojo',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
        shieldCount: 8,
        alertCount: 12,
        checkCount: 0,
      ),
      Report(
        id: 'sample-2',
        userCode: 'User-M9X1',
        zone: 5,
        category: 'alumbrado',
        description:
            'Poste de luz apagado en el Pasaje 4, cerca a la losa deportiva. Toda la cuadra está a oscuras.',
        imageUrl: null,
        tag: 'amarillo',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        shieldCount: 5,
        alertCount: 3,
        checkCount: 0,
      ),
      Report(
        id: 'sample-3',
        userCode: 'User-R4B2',
        zone: 2,
        category: 'sospechoso',
        description:
            '⚠️ ¡Buenas noticias! Serenazgo está patrullando la Av. Collique desde las 8 pm. Ruta segura para los vecinos.',
        tag: 'verde',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        shieldCount: 15,
        alertCount: 2,
        checkCount: 7,
      ),
    ];
  }
}
