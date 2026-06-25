import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  static const String _storageBucket = 'safezone-images';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://kpkdgejbjgmrbyemubmx.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtwa2RnZWpiamdtcmJ5ZW11Ym14Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2NjI5NTUsImV4cCI6MjA5NTIzODk1NX0.IRncOSBz7ALzvsazsQ4a1M3LaykBQ6Hsqd8GuE3LQf8',
    );
  }

  // Tablas
  String get profilesTable => 'profiles';
  String get reportsTable => 'reports';
  String get reactionsTable => 'reactions';
  String get chatMessagesTable => 'chat_messages';
  String get sosAlertsTable => 'sos_alerts';

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
