import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:safezone/app.dart';
import 'package:safezone/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar locale de timeago para español
  timeago.setLocaleMessages('es', timeago.EsMessages());

  // Intentar inicializar Supabase (opcional, la app funciona offline)
  try {
    await SupabaseService.initialize();
  } catch (e) {
    // La app funciona sin conexión a Supabase
    debugPrint('Supabase no disponible - modo offline');
  }

  runApp(const SafeZoneApp());
}
