import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

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

  /// Obtiene el usuario actual o crea uno nuevo anónimo
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final supabase = client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await supabase
        .from(profilesTable)
        .select()
        .eq('id', userId)
        .maybeSingle();

    return response;
  }

  /// Registra un nuevo perfil anónimo
  Future<void> createProfile(Map<String, dynamic> profile) async {
    await client.from(profilesTable).insert(profile);
  }

  /// Actualiza el perfil del usuario
  Future<void> updateProfile(String userId, Map<String, dynamic> data) async {
    await client.from(profilesTable).update(data).eq('id', userId);
  }
}
