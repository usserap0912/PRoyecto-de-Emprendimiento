import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:safezone/app.dart';
import 'package:safezone/services/power_saver_service.dart';
import 'package:safezone/services/supabase_service.dart';
import 'package:safezone/services/zonebot_service.dart';

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

  // ============================================================
  // INICIALIZAR ZONEBOT CON OPENAI
  // ============================================================
  // La API key se pasa exclusivamente via --dart-define para no
  // exponerla en el código fuente.
  //
  // Ejecutar la app con:
  //   flutter run --dart-define=OPENAI_API_KEY=sk-...
  //
  // O desde VS Code, configurar en .vscode/launch.json:
  //   "args": ["--dart-define=OPENAI_API_KEY=sk-..."]
  //
  // Si no se provee la key, ZoneBot usará respuestas locales
  // como fallback sin necesidad de OpenAI.
  // ============================================================
  const openaiKey = String.fromEnvironment('OPENAI_API_KEY');
  if (openaiKey.isNotEmpty) {
    try {
      await ZoneBotService.initialize(apiKey: openaiKey);
      debugPrint('ZoneBot: Inicializado correctamente con OpenAI');
    } catch (e) {
      debugPrint('ZoneBot: Error de inicialización: $e');
    }
  } else {
    debugPrint('ZoneBot: OPENAI_API_KEY no configurada. '
        'Usando respuestas locales como fallback. '
        'Ejecuta con: flutter run --dart-define=OPENAI_API_KEY=sk-...');
  }

  runApp(const SafeZoneApp());
}
