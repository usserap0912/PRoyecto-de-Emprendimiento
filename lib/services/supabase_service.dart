import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:safezone/services/location_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  static const String _storageBucket = 'safezone-images';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://kpkdgejbjgmrbyemubmx.supabase.co',
      publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtwa2RnZWpiamdtcmJ5ZW11Ym14Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2NjI5NTUsImV4cCI6MjA5NTIzODk1NX0.IRncOSBz7ALzvsazsQ4a1M3LaykBQ6Hsqd8GuE3LQf8',
    );
  }

  // Tablas
  String get profilesTable => 'profiles';
  String get reportsTable => 'reports';
  String get reactionsTable => 'reactions';
  String get chatMessagesTable => 'chat_messages';
  String get sosAlertsTable => 'sos_alerts';
  String get userScoresTable => 'user_scores';

  // ============================================================
  // PERFILES
  // ============================================================

  /// Obtiene un perfil por su código de usuario
  Future<Map<String, dynamic>?> getProfileByCode(String userCode) async {
    try {
      return await client
          .from(profilesTable)
          .select()
          .eq('user_code', userCode)
          .maybeSingle();
    } catch (e) {
      debugPrint('SupabaseService.getProfileByCode error: $e');
      return null;
    }
  }

  /// Crea un nuevo perfil anónimo. Retorna true si tuvo éxito.
  Future<bool> createProfile(Map<String, dynamic> profile) async {
    try {
      await client.from(profilesTable).insert(profile);
      return true;
    } catch (e) {
      debugPrint('SupabaseService.createProfile error: $e');
      return false;
    }
  }

  // ============================================================
  // REPORTES - REACCIONES
  // ============================================================

  /// Registra una reacción de un usuario a un reporte. 
  /// Si ya existe esa reacción, la elimina (toggle).
  Future<void> toggleReaction(
      String reportId, String userCode, String reactionType) async {
    try {
      // Verificar si ya existe la reacción
      final existing = await client
          .from(reactionsTable)
          .select()
          .eq('report_id', reportId)
          .eq('user_code', userCode)
          .eq('reaction_type', reactionType)
          .maybeSingle();

      if (existing != null) {
        // Ya existe → eliminar (toggle off)
        await client
            .from(reactionsTable)
            .delete()
            .eq('report_id', reportId)
            .eq('user_code', userCode)
            .eq('reaction_type', reactionType);
      } else {
        // No existe → insertar (toggle on)
        await client.from(reactionsTable).insert({
          'report_id': reportId,
          'user_code': userCode,
          'reaction_type': reactionType,
        });
      }
    } catch (e) {
      debugPrint('SupabaseService.toggleReaction error: $e');
    }
  }

  /// Obtiene las reacciones del usuario para un reporte
  Future<Set<String>> getUserReactions(
      String reportId, String userCode) async {
    try {
      final response = await client
          .from(reactionsTable)
          .select('reaction_type')
          .eq('report_id', reportId)
          .eq('user_code', userCode);

      return (response as List)
          .map((r) => r['reaction_type'] as String)
          .toSet();
    } catch (e) {
      debugPrint('SupabaseService.getUserReactions error: $e');
      return {};
    }
  }

  // ============================================================
  // ALERTAS S.O.S.
  // ============================================================

  /// Registra una alerta S.O.S. en la base de datos
  Future<bool> insertSosAlert(Map<String, dynamic> data) async {
    try {
      await client.from(sosAlertsTable).insert(data);
      return true;
    } catch (e) {
      debugPrint('SupabaseService.insertSosAlert error: $e');
      return false;
    }
  }

  // ============================================================
  // ARCHIVO DE REPORTES ANTIGUOS
  // ============================================================

  /// Ejecuta la función archive_old_reports() en Supabase.
  /// Mueve reportes > 7 días a archived_reports y los elimina de la tabla principal.
  /// Retorna la cantidad de reportes archivados.
  Future<int> archiveOldReports() async {
    try {
      final result = await client.rpc('archive_old_reports');
      if (result is int) return result;
      return 0;
    } catch (e) {
      debugPrint('SupabaseService.archiveOldReports error: $e');
      return 0;
    }
  }

  /// Obtiene reportes archivados con filtros opcionales.
  Future<List<Map<String, dynamic>>> getArchivedReports({
    int? zone,
    String? category,
    int limit = 50,
  }) async {
    try {
      var query = client.from('archived_reports').select();

      if (zone != null) {
        query = query.eq('zone', zone);
      }
      if (category != null) {
        query = query.eq('category', category);
      }

      final result = await query.order('created_at', ascending: false).limit(limit);
      return result;
    } catch (e) {
      debugPrint('SupabaseService.getArchivedReports error: $e');
      return [];
    }
  }

  // ============================================================
  // PUNTOS VECINALES
  // ============================================================

  /// Obtiene el nivel y puntos totales de un vecino.
  Future<Map<String, dynamic>?> getVecinoLevel(String userCode) async {
    try {
      final result = await client.rpc('get_vecino_level', params: {
        'p_user_code': userCode,
      });
      if (result is List && result.isNotEmpty) {
        return result[0] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('SupabaseService.getVecinoLevel error: $e');
      return null;
    }
  }

  /// Agrega puntos a un vecino por una acción.
  Future<int> addVecinoPoints({
    required String userCode,
    required int points,
    required String reason,
    String? description,
  }) async {
    try {
      final result = await client.rpc('add_vecino_points', params: {
        'p_user_code': userCode,
        'p_points': points,
        'p_reason': reason,
        'p_description': description,
      });
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('SupabaseService.addVecinoPoints error: $e');
      return 0;
    }
  }

  /// Realiza un check-in de zona segura.
  Future<Map<String, dynamic>> doSafeCheckin({
    required String userCode,
    required int zone,
    double? lat,
    double? lng,
  }) async {
    try {
      final result = await client.rpc('do_safe_checkin', params: {
        'p_user_code': userCode,
        'p_zone': zone,
        'p_lat': lat,
        'p_lng': lng,
      });
      return result as Map<String, dynamic>;
    } catch (e) {
      debugPrint('SupabaseService.doSafeCheckin error: $e');
      return {'success': false, 'message': 'Error al hacer check-in'};
    }
  }

  // ============================================================
  // STORAGE (imágenes y videos)
  // ============================================================

  /// Sube un archivo al Storage de Supabase y retorna la URL pública
  Future<String?> uploadFile(String filePath, {bool isVideo = false}) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('uploadFile: el archivo no existe en $filePath');
        return null;
      }

      final String ext = filePath.split('.').last.toLowerCase();
      final String fileName =
          '${const Uuid().v4()}.$ext';
      final String folder = isVideo ? 'videos' : 'images';
      final String storagePath = '$folder/$fileName';

      await client.storage.from(_storageBucket).upload(
            storagePath,
            file,
            fileOptions: FileOptions(
              contentType: isVideo ? 'video/$ext' : 'image/$ext',
            ),
          );

      final publicUrl =
          client.storage.from(_storageBucket).getPublicUrl(storagePath);
      return publicUrl;
    } catch (e) {
      debugPrint('SupabaseService.uploadFile error: $e');
      return null;
    }
  }

  // ============================================================
  // RANKING VECINAL
  // ============================================================

  /// Obtiene el ranking de los top vecinos por puntos.
  Future<List<Map<String, dynamic>>> getRanking({int limit = 10}) async {
    try {
      final result = await client.rpc('get_ranking', params: {
        'p_limit': limit,
      });
      return (result as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('SupabaseService.getRanking error: $e');
      return [];
    }
  }

  /// Canjea puntos por días Premium.
  Future<Map<String, dynamic>> redeemVecinoPoints({
    required String userCode,
    required int points,
  }) async {
    try {
      final result = await client.rpc('redeem_points', params: {
        'p_user_code': userCode,
        'p_points': points,
      });
      return result as Map<String, dynamic>;
    } catch (e) {
      debugPrint('SupabaseService.redeemVecinoPoints error: $e');
      return {'success': false, 'message': 'Error al canjear puntos: $e'};
    }
  }

  /// Obtiene el historial de canjes de un usuario.
  Future<List<Map<String, dynamic>>> getRedemptions(String userCode) async {
    try {
      final result = await client.rpc('get_redemptions', params: {
        'p_user_code': userCode,
      });
      return (result as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('SupabaseService.getRedemptions error: $e');
      return [];
    }
  }

  // ============================================================
  // NOTIFICACIONES EN TIEMPO REAL: Reportes "Robo"
  // ============================================================

  StreamSubscription<List<Map<String, dynamic>>>? _roboSubscription;

  /// Inicia la escucha de nuevos reportes de categoría "Robo".
  /// Cuando se detecta uno, calcula:
  ///   - Tiempo transcurrido (timeago)
  ///   - Distancia desde la ubicación actual del vecino
  ///   - Cantidad de reportes similares en la misma zona (últimas 24h)
  ///
  /// [onRoboDetected] se invoca con los datos calculados para mostrar una notificación.
  void subscribeToRoboNotifications({
    required void Function(RoboNotificationData data) onRoboDetected,
  }) {
    try {
      _roboSubscription = client
          .from(reportsTable)
          .stream(primaryKey: ['id'])
          .eq('category', 'robo')
          .order('created_at', ascending: false)
          .limit(50)
          .listen((List<Map<String, dynamic>> reports) {
        if (reports.isEmpty) return;

        // Solo procesar el reporte más reciente (primero del stream)
        final latest = reports.first;
        _processRoboReport(latest, onRoboDetected, reports);
      }, onError: (Object error) {
        debugPrint('Error en stream de reportes Robo: $error');
      });
    } catch (e) {
      debugPrint('Error iniciando stream de Robo: $e');
    }
  }

  /// Procesa un reporte de robo y calcula los datos enriquecidos para notificación.
  Future<void> _processRoboReport(
    Map<String, dynamic> report,
    void Function(RoboNotificationData data) onRoboDetected,
    List<Map<String, dynamic>> allRoboReports,
  ) async {
    try {
      // 1. Tiempo transcurrido con timeago
      final createdAtStr = report['created_at'] as String? ?? '';
      final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
      final timeAgoText = timeago.format(createdAt, locale: 'es');

      // 2. Distancia desde la ubicación actual del vecino
      final reportLat = (report['lat'] ?? report['latitude']) as num? ?? 0;
      final reportLng = (report['lng'] ?? report['longitude']) as num? ?? 0;

      String distanceText = 'Desconocida';
      try {
        final locationService = LocationService();
        final position = await locationService.getCurrentLocation();
        if (position != null) {
          final meters = LocationService.calculateDistance(
            position.latitude,
            position.longitude,
            reportLat.toDouble(),
            reportLng.toDouble(),
          );
          distanceText = LocationService.formatDistance(meters);
        } else {
          // Fallback: distancia desde el centro de Collique
          final meters = LocationService.calculateDistance(
            LocationService.colliqueLat,
            LocationService.colliqueLng,
            reportLat.toDouble(),
            reportLng.toDouble(),
          );
          distanceText = '~${LocationService.formatDistance(meters)}';
        }
      } catch (e) {
        debugPrint('Error calculando distancia: $e');
      }

      // 3. Reportes similares en la misma zona (últimas 24h)
      final zone = report['zone'] as int? ?? 0;
      final now = DateTime.now();
      final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));

      final similarCount = allRoboReports.where((r) {
        final rZone = r['zone'] as int?;
        final rCreatedAtStr = r['created_at'] as String?;
        final rCreatedAt = rCreatedAtStr != null
            ? DateTime.tryParse(rCreatedAtStr)
            : null;
        return rZone == zone &&
            rCreatedAt != null &&
            rCreatedAt.isAfter(twentyFourHoursAgo);
      }).length;

      final data = RoboNotificationData(
        timeAgo: timeAgoText,
        distance: distanceText,
        similarReportsCount: similarCount,
        zone: zone,
        latitude: reportLat.toDouble(),
        longitude: reportLng.toDouble(),
        reportId: report['id'] as String? ?? '',
      );

      onRoboDetected(data);
    } catch (e) {
      debugPrint('Error procesando reporte Robo: $e');
    }
  }

  /// Detiene la suscripción de notificaciones de Robo.
  void unsubscribeFromRoboNotifications() {
    _roboSubscription?.cancel();
    _roboSubscription = null;
  }

  /// Verifica si el bucket de Storage existe, si no intenta crearlo
  Future<bool> ensureStorageBucket() async {
    try {
      // Intentar listar buckets para ver si existe
      try {
        await client.storage.from(_storageBucket).list();
        return true; // Ya existe
      } catch (_) {
        // Bucket no existe - no podemos crearlo con anon key
        debugPrint(
            'Storage bucket "$_storageBucket" no existe. Créalo en Supabase Dashboard > Storage.');
        return false;
      }
    } catch (e) {
      debugPrint('SupabaseService.ensureStorageBucket error: $e');
      return false;
    }
  }
}

// ============================================================
// MODELO: Datos de notificación para reporte "Robo reportado"
// ============================================================

/// Contiene los datos calculados enriquecidos para una notificación
/// de "Robo reportado" (timeago, distancia, reportes similares).
class RoboNotificationData {
  final String title;
  final String timeAgo;
  final String distance;
  final int similarReportsCount;
  final int zone;
  final double latitude;
  final double longitude;
  final String reportId;

  RoboNotificationData({
    this.title = 'Robo reportado',
    required this.timeAgo,
    required this.distance,
    required this.similarReportsCount,
    required this.zone,
    required this.latitude,
    required this.longitude,
    required this.reportId,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'time_ago': timeAgo,
    'distance': distance,
    'similar_reports': similarReportsCount,
    'zone': zone,
    'latitude': latitude,
    'longitude': longitude,
    'report_id': reportId,
  };

  @override
  String toString() =>
      'RoboNotificationData(title: $title, timeAgo: $timeAgo, '
      'distance: $distance, similarReports: $similarReportsCount, '
      'zone: $zone)';
}

