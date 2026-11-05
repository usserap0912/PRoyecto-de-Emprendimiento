import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:safezone/app.dart';
import 'package:safezone/services/power_saver_service.dart';
import 'package:safezone/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar locale de timeago para español
  timeago.setLocaleMessages('es', timeago.EsMessages());

  // Inicializar Modo Ahorro (configura sonidos según preferencias guardadas)
  PowerSaverService().initialize();

  // Intentar inicializar Supabase (opcional, la app funciona offline)
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase no disponible - modo offline');
  }

  runApp(const SafeZoneApp());
}
