import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:safezone/models/comment_submission.dart';
import 'package:safezone/models/report.dart';
import 'package:safezone/models/report_comment.dart';
import 'package:safezone/models/report_form_config.dart';
import 'package:safezone/models/report_reaction.dart';
import 'package:safezone/models/report_submission.dart';
import 'package:safezone/models/wall_time_filter.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ReportGateway {
  Future<bool> profileExists(String userCode);

  Future<String?> uploadEvidence(String path, {required bool isVideo});

  Future<Map<String, dynamic>> insertReport(Map<String, dynamic> payload);
}

class SupabaseReportGateway implements ReportGateway {
  SupabaseReportGateway({SupabaseService? supabase})
    : _supabase = supabase ?? SupabaseService();

  static const Duration _operationTimeout = Duration(seconds: 15);
  final SupabaseService _supabase;

  @override
  Future<bool> profileExists(String userCode) async {
    final profile = await _supabase.client
        .from(_supabase.profilesTable)
        .select('user_code')
        .eq('user_code', userCode)
        .maybeSingle()
        .timeout(_operationTimeout);
    return profile != null;
  }

  @override
  Future<String?> uploadEvidence(String path, {required bool isVideo}) {
    return _supabase
        .uploadFile(path, isVideo: isVideo)
        .timeout(_operationTimeout);
  }

  @override
  Future<Map<String, dynamic>> insertReport(Map<String, dynamic> payload) {
    return _supabase.client
        .from(_supabase.reportsTable)
        .insert(payload)
        .select()
        .single()
        .timeout(_operationTimeout);
  }
}

abstract interface class WallInteractionGateway {
  Stream<List<Map<String, dynamic>>> watchReactions(String reportId);

  Future<List<Map<String, dynamic>>> fetchReactions(String reportId);

  Future<Map<String, dynamic>> toggleReaction({
    required String reportId,
    required String userCode,
    required String emoji,
  });

  Stream<List<Map<String, dynamic>>> watchComments(String reportId);

  Future<Map<String, dynamic>> insertComment({
    required String reportId,
    required String userCode,
    required String content,
  });
}

class SupabaseWallInteractionGateway implements WallInteractionGateway {
  SupabaseWallInteractionGateway({SupabaseService? supabase})
    : _supabase = supabase ?? SupabaseService();

  static const _timeout = Duration(seconds: 12);
  final SupabaseService _supabase;

  @override
  Stream<List<Map<String, dynamic>>> watchReactions(String reportId) {
    return _supabase.client
        .from(_supabase.reactionsTable)
        .stream(primaryKey: ['id'])
        .eq('report_id', reportId)
        .order('created_at');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReactions(String reportId) async {
    final rows = await _supabase.client
        .from(_supabase.reactionsTable)
        .select('id, report_id, user_code, reaction_type, created_at')
        .eq('report_id', reportId)
        .order('created_at')
        .timeout(_timeout);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Map<String, dynamic>> toggleReaction({
    required String reportId,
    required String userCode,
    required String emoji,
  }) async {
    final existing = await _supabase.client
        .from(_supabase.reactionsTable)
        .select('id, reaction_type')
        .eq('report_id', reportId)
        .eq('user_code', userCode)
        .timeout(_timeout);
    final rows = List<Map<String, dynamic>>.from(existing);
    final removes = rows.length == 1 && rows.single['reaction_type'] == emoji;

    if (rows.isNotEmpty) {
      await _supabase.client
          .from(_supabase.reactionsTable)
          .delete()
          .eq('report_id', reportId)
          .eq('user_code', userCode)
          .timeout(_timeout);
    }
    if (removes) {
      return <String, dynamic>{'action': 'removed', 'reaction_type': null};
    }

    final inserted = await _supabase.client
        .from(_supabase.reactionsTable)
        .insert({
          'report_id': reportId,
          'user_code': userCode,
          'reaction_type': emoji,
        })
        .select('reaction_type')
        .single()
        .timeout(_timeout);
    return <String, dynamic>{
      'action': 'set',
      'reaction_type': inserted['reaction_type'],
    };
  }

  @override
  Stream<List<Map<String, dynamic>>> watchComments(String reportId) {
    return _supabase.client
        .from('report_comments')
        .stream(primaryKey: ['id'])
        .eq('report_id', reportId)
        .order('created_at');
  }

  @override
  Future<Map<String, dynamic>> insertComment({
    required String reportId,
    required String userCode,
    required String content,
  }) {
    return _supabase.client
        .from('report_comments')
        .insert({
          'report_id': reportId,
          'user_code': userCode,
          'comment_text': content,
        })
        .select('id, report_id, user_code, comment_text, created_at')
        .single()
        .timeout(_timeout);
  }
}

class ReportService {
  ReportService({
    SupabaseService? supabase,
    ReportGateway? gateway,
    WallInteractionGateway? wallGateway,
  }) : _supabase = supabase ?? SupabaseService(),
       _gateway = gateway ?? SupabaseReportGateway(supabase: supabase),
       _wallGateway =
           wallGateway ?? SupabaseWallInteractionGateway(supabase: supabase);

  final SupabaseService _supabase;
  final ReportGateway _gateway;
  final WallInteractionGateway _wallGateway;
  bool _submissionInFlight = false;

  static final StreamController<Report> _createdReportController =
      StreamController<Report>.broadcast();

  Stream<Report> get createdReports => _createdReportController.stream;

  static bool isVisibleInWall(
    Report report, {
    WallTimeFilter filter = WallTimeFilter.last7Days,
    DateTime? now,
  }) {
    return filter.includes(report.createdAt, now: now);
  }

  // ============================================================
  // CONSULTAS CON FILTRO TEMPORAL
  // ============================================================

  /// Obtiene como máximo 50 publicaciones dentro de la ventana elegida.
  /// El filtro se aplica en Supabase antes de descargar los registros.
  Future<List<Report>> getReports({
    int? zone,
    WallTimeFilter timeFilter = WallTimeFilter.last7Days,
  }) async {
    try {
      var query = _supabase.client.from(_supabase.reportsTable).select();

      if (zone != null) {
        query = query.eq('zone', zone);
      }

      query = query.gte(
        'created_at',
        timeFilter.cutoff(DateTime.now()).toIso8601String(),
      );

      final response = await query
          .order('created_at', ascending: false)
          .limit(50);

      final reports = (response as List)
          .map((item) => Report.fromMap(item as Map<String, dynamic>))
          .toList();
      return timeFilter.filterAndSort(reports);
    } catch (e) {
      debugPrint('ReportService.getReports error: $e');
      rethrow;
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
    WallTimeFilter timeFilter = WallTimeFilter.last7Days,
    required void Function(List<Report> reports) onData,
    void Function(Object error)? onError,
  }) {
    try {
      // Construimos la cadena completa sin asignaciones intermedias
      // para evitar conflictos de tipos en la API de Supabase
      dynamic query = _supabase.client
          .from(_supabase.reportsTable)
          .stream(primaryKey: ['id']);

      if (zone != null) query = query.eq('zone', zone);

      query = query.gte(
        'created_at',
        timeFilter.cutoff(DateTime.now()).toIso8601String(),
      );

      _realtimeSubscription =
          (query
                      .order('created_at', ascending: false)
                      .limit(50)
                      .map((maps) => maps.map((m) => Report.fromMap(m)))
                  as Stream)
              .listen(
                (reports) => onData(
                  timeFilter.filterAndSort(reports as Iterable<Report>),
                ),
                onError: (Object error) {
                  debugPrint('ReportService reports realtime error: $error');
                  onError?.call(error);
                },
              );
    } catch (e) {
      debugPrint('ReportService.subscribeToRealtime error: $e');
    }
  }

  /// Actualiza la suscripción en tiempo real con un nuevo filtro
  void resubscribe({
    int? zone,
    WallTimeFilter timeFilter = WallTimeFilter.last7Days,
    required void Function(List<Report> reports) onData,
    void Function(Object error)? onError,
  }) {
    unsubscribeFromRealtime();
    subscribeToRealtime(
      zone: zone,
      timeFilter: timeFilter,
      onData: onData,
      onError: onError,
    );
  }

  /// Detiene la suscripción
  void unsubscribeFromRealtime() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }

  // ============================================================
  // CRUD DE REPORTES
  // ============================================================

  Future<ReportSubmissionResult> createReport(
    ReportDraft draft, {
    String? localImagePath,
    String? localVideoPath,
  }) async {
    if (_submissionInFlight) {
      return const ReportSubmissionResult.failure(
        failure: ReportSubmissionFailure.duplicate,
        message: 'El reporte ya se está enviando.',
      );
    }
    if (!ReportFormConfig.supportedCategoryValues.contains(draft.category)) {
      return const ReportSubmissionResult.failure(
        failure: ReportSubmissionFailure.invalidCategory,
        message: 'La categoría seleccionada no es válida.',
      );
    }
    if (!ReportFormConfig.supportedSeverityValues.contains(draft.severity)) {
      return const ReportSubmissionResult.failure(
        failure: ReportSubmissionFailure.invalidSeverity,
        message: 'Selecciona un nivel de gravedad válido.',
      );
    }
    if (draft.zone < 1 || draft.zone > 10) {
      return const ReportSubmissionResult.failure(
        failure: ReportSubmissionFailure.invalidZone,
        message: 'La zona seleccionada no es válida.',
      );
    }

    _submissionInFlight = true;
    var operation = 'profile.select';
    try {
      if (!await _gateway.profileExists(draft.userCode)) {
        return const ReportSubmissionResult.failure(
          failure: ReportSubmissionFailure.missingProfile,
          message:
              'No pudimos validar tu perfil. Conservamos el reporte para que puedas reintentar.',
        );
      }

      String? imageUrl;
      if (localImagePath != null) {
        operation = 'storage.image.upload';
        imageUrl = await _gateway.uploadEvidence(
          localImagePath,
          isVideo: false,
        );
        if (imageUrl == null) {
          return const ReportSubmissionResult.failure(
            failure: ReportSubmissionFailure.mediaUpload,
            message:
                'No pudimos subir la foto. El formulario se conserva para reintentar.',
          );
        }
      }

      String? videoUrl;
      if (localVideoPath != null) {
        operation = 'storage.video.upload';
        videoUrl = await _gateway.uploadEvidence(localVideoPath, isVideo: true);
        if (videoUrl == null) {
          return const ReportSubmissionResult.failure(
            failure: ReportSubmissionFailure.mediaUpload,
            message:
                'No pudimos subir el video. El formulario se conserva para reintentar.',
          );
        }
      }

      operation = 'insert';
      final inserted = await _gateway.insertReport(
        draft.toInsertPayload(imageUrl: imageUrl, videoUrl: videoUrl),
      );
      final report = Report.fromMap(inserted);
      _createdReportController.add(report);
      return ReportSubmissionResult.success(report);
    } catch (error, stackTrace) {
      final result = _classifySubmissionError(error);
      _logSubmissionError(operation, error, result, stackTrace);
      return result;
    } finally {
      _submissionInFlight = false;
    }
  }

  ReportSubmissionResult _classifySubmissionError(Object error) {
    if (error is TimeoutException) {
      return const ReportSubmissionResult.failure(
        failure: ReportSubmissionFailure.timeout,
        message: 'El servidor tardó demasiado. Intenta enviar nuevamente.',
      );
    }
    if (error is PostgrestException) {
      final code = error.code?.toUpperCase();
      if (code == '23503') {
        return ReportSubmissionResult.failure(
          failure: ReportSubmissionFailure.missingProfile,
          message:
              'Tu perfil no está registrado en el servidor. Conservamos el reporte para reintentar.',
          technicalCode: error.code,
        );
      }
      if (code == '42501' || code == '401' || code == '403') {
        return ReportSubmissionResult.failure(
          failure: ReportSubmissionFailure.authentication,
          message: 'Supabase no autorizó el envío. Revisa tu sesión.',
          technicalCode: error.code,
        );
      }
      if (code == '42703' || code == 'PGRST204' || code == '42P01') {
        return ReportSubmissionResult.failure(
          failure: ReportSubmissionFailure.schema,
          message: 'El servidor de reportes necesita una actualización.',
          technicalCode: error.code,
        );
      }
      return ReportSubmissionResult.failure(
        failure: ReportSubmissionFailure.rejected,
        message:
            'Supabase rechazó el reporte. Revisa los datos e intenta nuevamente.',
        technicalCode: error.code,
      );
    }
    if (error is AuthException) {
      return ReportSubmissionResult.failure(
        failure: ReportSubmissionFailure.authentication,
        message: 'No pudimos autorizar el envío. Revisa tu sesión.',
        technicalCode: error.code ?? error.statusCode,
      );
    }
    return const ReportSubmissionResult.failure(
      failure: ReportSubmissionFailure.backendUnavailable,
      message: 'No pudimos enviar el reporte. Intenta nuevamente.',
    );
  }

  void _logSubmissionError(
    String operation,
    Object error,
    ReportSubmissionResult result,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    final rawMessage = error is PostgrestException
        ? error.message
        : error.toString();
    final sanitized = rawMessage
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._-]+'), 'Bearer [REDACTED]')
        .replaceAll(
          RegExp(r'[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'),
          '[REDACTED_TOKEN]',
        )
        .replaceAll(RegExp(r'apikey=[^&\s]+'), 'apikey=[REDACTED]');
    debugPrint(
      '[REPORT][$operation] code=${result.technicalCode ?? 'none'} '
      'failure=${result.failure.name} error=$sanitized',
    );
    debugPrintStack(
      label: '[REPORT][$operation] stack',
      stackTrace: stackTrace,
    );
  }

  // ============================================================
  // REACCIONES
  // ============================================================

  Stream<ReactionSummary> watchReactionSummary(
    String reportId, {
    required String currentUserCode,
  }) {
    return _wallGateway.watchReactions(reportId).map((rows) {
      final reactions = rows.map(ReportReaction.fromMap);
      return ReactionSummary.fromReactions(
        reactions,
        currentUserCode: currentUserCode,
      );
    });
  }

  /// Mantiene compatibilidad con la tarjeta antigua mientras comparte la
  /// misma regla de una reacción activa por usuario/publicación.
  Future<ReactionMutationResult> toggleReaction(
    String reportId,
    String userCode,
    String reactionType,
  ) => toggleEmojiReaction(reportId, userCode, reactionType);

  Future<ReactionMutationResult> toggleEmojiReaction(
    String reportId,
    String userCode,
    String reactionType,
  ) async {
    final emoji = reactionType.trim();
    if (emoji.isEmpty || emoji.length > 32) {
      return const ReactionMutationResult.failure(
        'Selecciona un solo emoji válido.',
      );
    }
    try {
      final response = await _wallGateway.toggleReaction(
        reportId: reportId,
        userCode: userCode,
        emoji: emoji,
      );
      final action = response['action'] == 'removed'
          ? ReactionMutationAction.removed
          : ReactionMutationAction.set;
      return ReactionMutationResult.success(
        action: action,
        emoji: response['reaction_type'] as String?,
      );
    } catch (error, stackTrace) {
      _logWallError('REACTION', 'toggle', error, stackTrace);
      final missingRpc =
          error is PostgrestException &&
          (error.code == 'PGRST202' || error.code == '42883');
      return ReactionMutationResult.failure(
        missingRpc
            ? 'Las reacciones necesitan la migración del Muro.'
            : 'No pudimos guardar tu reacción. Intenta nuevamente.',
      );
    }
  }

  /// Obtiene las reacciones del usuario para un reporte
  Future<Set<String>> getUserReactions(String reportId, String userCode) async {
    try {
      final reactions = (await _wallGateway.fetchReactions(
        reportId,
      )).map(ReportReaction.fromMap);
      final summary = ReactionSummary.fromReactions(
        reactions,
        currentUserCode: userCode,
      );
      return summary.currentUserEmoji == null
          ? <String>{}
          : <String>{summary.currentUserEmoji!};
    } catch (error, stackTrace) {
      _logWallError('REACTION', 'select', error, stackTrace);
      return <String>{};
    }
  }

  // ============================================================
  // ARCHIVO DE REPORTES ANTIGUOS
  // ============================================================

  /// Archiva reportes más antiguos que 7 días.
  /// Retorna cuántos reportes fueron archivados.
  Future<int> archiveOldReports() async {
    return _supabase.archiveOldReports();
  }

  /// Obtiene reportes archivados del historial.
  Future<List<Report>> getArchivedReports({
    int? zone,
    String? category,
    int limit = 50,
  }) async {
    final data = await _supabase.getArchivedReports(
      zone: zone,
      category: category,
      limit: limit,
    );
    return data.map((m) => Report.fromMap(m)).toList();
  }

  // ============================================================
  // COMENTARIOS
  // ============================================================

  /// Obtiene los comentarios de un reporte en tiempo real
  Stream<List<ReportComment>> getCommentsStream(String reportId) {
    return _wallGateway.watchComments(reportId).map((rows) {
      final comments = rows.map(ReportComment.fromMap).toList();
      comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return comments;
    });
  }

  /// Inserta un nuevo comentario
  Future<CommentSubmissionResult> addComment({
    required String reportId,
    required String userCode,
    required String content,
  }) async {
    final sanitizedContent = content.trim();
    if (sanitizedContent.isEmpty) {
      return const CommentSubmissionResult.failure(
        failure: CommentSubmissionFailure.empty,
        message: 'Escribe un comentario antes de enviarlo.',
      );
    }
    try {
      final inserted = await _wallGateway.insertComment(
        reportId: reportId,
        userCode: userCode,
        content: sanitizedContent,
      );
      return CommentSubmissionResult.success(ReportComment.fromMap(inserted));
    } catch (error, stackTrace) {
      _logWallError('COMMENT', 'insert', error, stackTrace);
      if (error is TimeoutException) {
        return const CommentSubmissionResult.failure(
          failure: CommentSubmissionFailure.timeout,
          message: 'El servidor tardó demasiado. Tu texto se conserva.',
        );
      }
      if (error is PostgrestException) {
        final code = error.code?.toUpperCase();
        if (code == '23503') {
          final details = '${error.message} ${error.details}'.toLowerCase();
          final missingProfile =
              details.contains('user_code') || details.contains('profiles');
          return CommentSubmissionResult.failure(
            failure: missingProfile
                ? CommentSubmissionFailure.missingProfile
                : CommentSubmissionFailure.missingPublication,
            message: missingProfile
                ? 'Tu perfil no está registrado para comentar.'
                : 'Esta publicación ya no admite comentarios en el Muro.',
          );
        }
        if (code == '42501' || code == '401' || code == '403') {
          return const CommentSubmissionResult.failure(
            failure: CommentSubmissionFailure.authentication,
            message: 'Supabase no autorizó el comentario. Revisa tu sesión.',
          );
        }
        if (code == '42703' || code == 'PGRST204' || code == '42P01') {
          return const CommentSubmissionResult.failure(
            failure: CommentSubmissionFailure.schema,
            message: 'El esquema de comentarios necesita actualización.',
          );
        }
      }
      return const CommentSubmissionResult.failure(
        failure: CommentSubmissionFailure.backend,
        message: 'No pudimos publicar el comentario. Tu texto se conserva.',
      );
    }
  }

  void _logWallError(
    String scope,
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    final raw = error is PostgrestException ? error.message : error.toString();
    final sanitized = raw
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._-]+'), 'Bearer [REDACTED]')
        .replaceAll(
          RegExp(r'[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'),
          '[REDACTED_TOKEN]',
        )
        .replaceAll(RegExp(r'apikey=[^&\s]+'), 'apikey=[REDACTED]');
    final code = error is PostgrestException ? error.code : null;
    debugPrint('[$scope][$operation] code=${code ?? 'none'} error=$sanitized');
    debugPrintStack(
      label: '[$scope][$operation] stack',
      stackTrace: stackTrace,
    );
  }
}
