import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/models/report_comment.dart';
import 'package:safezone/services/supabase_service.dart';

class ReportService {
  final SupabaseService _supabase = SupabaseService();

  // ============================================================
  // CONSULTAS CON FILTRO TEMPORAL
  // ============================================================

  /// Obtiene reportes aplicando un filtro de tiempo.
  /// [timeFilter]: 'today', '1day', '2days', 'week', o null (sin filtro)
  Future<List<Report>> getReports({
    int? zone,
    String? timeFilter,
  }) async {
    try {
      var query = _supabase.client.from(_supabase.reportsTable).select();

      if (zone != null) {
        query = query.eq('zone', zone);
      }

      // Aplicar filtro temporal sobre 'created_at'
      if (timeFilter != null) {
        final now = DateTime.now();
        DateTime since;

        switch (timeFilter) {
          case 'today':
            since = DateTime(now.year, now.month, now.day);
            break;
          case '1day':
            since = now.subtract(const Duration(days: 1));
            break;
          case '2days':
            since = now.subtract(const Duration(days: 2));
            break;
          case 'week':
            since = now.subtract(const Duration(days: 7));
            break;
          default:
            since = now.subtract(const Duration(days: 30));
        }

        query = query.gte('created_at', since.toIso8601String());
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

  // ============================================================
  // STREAM EN TIEMPO REAL (con .stream() en lugar de channel)
  // ============================================================

  /// Obtiene un stream de reportes en tiempo real filtrados por zona.
  /// [timeFilter] opcional para filtrar por tiempo.
  StreamSubscription? _realtimeSubscription;

  /// Inicia la escucha en tiempo real usando .stream() de Supabase.
  void subscribeToRealtime({
    int? zone,
    String? timeFilter,
    required void Function(List<Report> reports) onData,
  }) {
    try {
      // Construimos la cadena completa sin asignaciones intermedias
      // para evitar conflictos de tipos en la API de Supabase
      dynamic query = _supabase.client
          .from(_supabase.reportsTable)
          .stream(primaryKey: ['id']);

      if (zone != null) query = query.eq('zone', zone);

      if (timeFilter != null) {
        final now = DateTime.now();
        DateTime since;
        switch (timeFilter) {
          case 'today':
            since = DateTime(now.year, now.month, now.day);
            break;
          case '1day':
            since = now.subtract(const Duration(days: 1));
            break;
          case '2days':
            since = now.subtract(const Duration(days: 2));
            break;
          case 'week':
            since = now.subtract(const Duration(days: 7));
            break;
          default:
            since = now.subtract(const Duration(days: 30));
        }
        query = query.gte('created_at', since.toIso8601String());
      }

      _realtimeSubscription = (query
          .order('created_at', ascending: false)
          .limit(50)
          .map((maps) => maps.map((m) => Report.fromMap(m))) as Stream)
          .listen((reports) {
        onData((reports as Iterable<Report>).toList());
      });
    } catch (e) {
      debugPrint('ReportService.subscribeToRealtime error: $e');
    }
  }

  /// Actualiza la suscripción en tiempo real con un nuevo filtro
  void resubscribe({
    int? zone,
    String? timeFilter,
    required void Function(List<Report> reports) onData,
  }) {
    unsubscribeFromRealtime();
    subscribeToRealtime(zone: zone, timeFilter: timeFilter, onData: onData);
  }

  /// Detiene la suscripción
  void unsubscribeFromRealtime() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }

  // ============================================================
  // CRUD DE REPORTES
  // ============================================================

  Future<bool> createReport(Report report,
      {String? localImagePath, String? localVideoPath}) async {
    try {
      Map<String, dynamic> reportData = report.toMap();

      if (localImagePath != null && File(localImagePath).existsSync()) {
        final imageUrl = await _supabase.uploadFile(localImagePath);
        if (imageUrl != null) reportData['image_url'] = imageUrl;
      }

      if (localVideoPath != null && File(localVideoPath).existsSync()) {
        final videoUrl =
            await _supabase.uploadFile(localVideoPath, isVideo: true);
        if (videoUrl != null) reportData['video_url'] = videoUrl;
      }

      reportData.remove('id');
      await _supabase.client.from(_supabase.reportsTable).insert(reportData);
      return true;
    } catch (e) {
      debugPrint('ReportService.createReport error: $e');
      return false;
    }
  }

  // ============================================================
  // REACCIONES (compatibilidad con post_card.dart)
  // ============================================================

  /// Alterna una reacción (mantiene compatibilidad con PostCard)
  Future<void> toggleReaction(
      String reportId, String userCode, String reactionType) async {
    await _supabase.toggleReaction(reportId, userCode, reactionType);
  }

  /// Alterna una reacción emoji
  Future<void> toggleEmojiReaction(
      String reportId, String userCode, String reactionType) async {
    await _supabase.toggleReaction(reportId, userCode, reactionType);
  }

  /// Obtiene las reacciones del usuario para un reporte
  Future<Set<String>> getUserReactions(
      String reportId, String userCode) async {
    return _supabase.getUserReactions(reportId, userCode);
  }

  // ============================================================
  // COMENTARIOS
  // ============================================================

  String get _commentsTable => 'report_comments';

  /// Obtiene los comentarios de un reporte en tiempo real
  Stream<List<ReportComment>> getCommentsStream(String reportId) {
    return _supabase.client
        .from(_commentsTable)
        .stream(primaryKey: ['id'])
        .eq('report_id', reportId)
        .order('created_at', ascending: true)
        .map((maps) =>
            maps.map((m) => ReportComment.fromMap(m)).toList());
  }

  /// Inserta un nuevo comentario
  Future<bool> addComment({
    required String reportId,
    required String userCode,
    required String content,
  }) async {
    try {
      await _supabase.client.from(_commentsTable).insert({
        'report_id': reportId,
        'user_code': userCode,
        'content': content,
      });
      return true;
    } catch (e) {
      debugPrint('ReportService.addComment error: $e');
      return false;
    }
  }

  // ============================================================
  // DATOS DE EJEMPLO (fallback offline)
  // ============================================================

  List<Report> _getSampleReports() {
    return [
      Report(
        id: 'sample-1',
        userCode: 'User-A7K3',
        zone: 3,
        category: 'robo',
        description:
            'Moto lineal negra sospechosa dando vueltas en la Av. Revolución desde las 10 pm.',
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
            'Poste de luz apagado en el Pasaje 4, cerca a la losa deportiva.',
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
            'Serenazgo está patrullando la Av. Collique desde las 8 pm.',
        tag: 'verde',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        shieldCount: 15,
        alertCount: 2,
        checkCount: 7,
      ),
    ];
  }
}
