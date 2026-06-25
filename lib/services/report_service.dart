import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/services/supabase_service.dart';

class ReportService {
  final SupabaseService _supabase = SupabaseService();

  /// Obtiene todos los reportes, opcionalmente filtrados por zona
  Future<List<Report>> getReports({int? zone}) async {
    try {
      var query = _supabase.client.from(_supabase.reportsTable).select();

      if (zone != null) {
        query = query.eq('zone', zone);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List)
          .map((item) => Report.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('ReportService.getReports error: $e');
      return _getSampleReports();
    }
  }

  /// Crea un nuevo reporte. Si hay imágenes/videos, los sube primero a Storage.
  Future<bool> createReport(Report report,
      {String? localImagePath, String? localVideoPath}) async {
    try {
      Map<String, dynamic> reportData = report.toMap();

      // Subir imagen si existe
      if (localImagePath != null && File(localImagePath).existsSync()) {
        final imageUrl = await _supabase.uploadFile(localImagePath);
        if (imageUrl != null) {
          reportData['image_url'] = imageUrl;
        }
      }

      // Subir video si existe
      if (localVideoPath != null && File(localVideoPath).existsSync()) {
        final videoUrl =
            await _supabase.uploadFile(localVideoPath, isVideo: true);
        if (videoUrl != null) {
          reportData['video_url'] = videoUrl;
        }
      }

      // Quitar el id local para que Supabase lo genere automáticamente
      reportData.remove('id');

      await _supabase.client.from(_supabase.reportsTable).insert(reportData);
      return true;
    } catch (e) {
      debugPrint('ReportService.createReport error: $e');
      return false;
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
      debugPrint('ReportService.updateReportStatus error: $e');
    }
  }

  /// Reacciona a un reporte (toggle: agrega o quita la reacción)
  Future<void> toggleReaction(
      String reportId, String userCode, String reactionType) async {
    await _supabase.toggleReaction(reportId, userCode, reactionType);
  }

  /// Obtiene las reacciones del usuario para un reporte
  Future<Set<String>> getUserReactions(
      String reportId, String userCode) async {
    return _supabase.getUserReactions(reportId, userCode);
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
