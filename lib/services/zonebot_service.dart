import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:safezone/models/zonebot_message.dart';

// ============================================================
// ZONEBOT SERVICE
// ============================================================
// Servicio que orquesta la lógica del bot guardián:
//   - Consejo creativo del día con persistencia local
//   - Personalidad vía system prompt (para futura integración AI)
//   - Respuestas contextuales sobre el uso de SafeZone
// ============================================================

/// Servicio principal de ZoneBot.
///
/// Gestiona el consejo de seguridad diario con caché en SharedPreferences
/// y proporciona el system prompt de personalidad para la API de IA.
/// Cuando la API no está disponible, usa una lista curada de consejos
/// creativos con el estilo lúdico de ZoneBot.
class ZoneBotService {
  static const String _prefsKeyTip = 'zonebot_daily_tip';
  static const String _prefsKeyDate = 'zonebot_daily_tip_date';
  static const String _prefsKeyHistory = 'zonebot_chat_history';

  // ============================================================
  // SISTEMA DE CRÉDITOS (tokens de uso)
  // ============================================================
  // Los usuarios gratis tienen:
  //   - 15 mensajes por enviar (se consumen al enviar)
  //   - 3 resets de conversación (se consumen al reiniciar)
  // Los usuarios premium tienen todo ilimitado.
  // ============================================================

  static const String _prefsKeyMsgTokens = 'zonebot_msg_tokens';
  static const String _prefsKeyResetTokens = 'zonebot_reset_tokens';
  static const String _prefsKeyPremium = 'zonebot_is_premium';
  static const String _prefsKeyLastRefresh = 'zonebot_last_refresh';

  /// Créditos de mensajes disponibles para el usuario gratis.
  static const int _maxMessageTokens = 15;

  /// Créditos de reset disponibles para el usuario gratis.
  static const int _maxResetTokens = 3;

  static int _messageTokens = _maxMessageTokens;
  static int _resetTokens = _maxResetTokens;
  static bool _isPremium = false;

  static int get messageTokens => _messageTokens;
  static int get resetTokens => _resetTokens;
  static bool get isPremium => _isPremium;
  static int get maxMessageTokens => _maxMessageTokens;
  static int get maxResetTokens => _maxResetTokens;

  // ============================================================
  // CONTADOR DE TOKENS
  // ============================================================

  /// Total de tokens usados en la sesión actual.
  static int _totalTokensUsed = 0;

  /// Total de tokens de entrada (prompt).
  static int _totalPromptTokens = 0;

  /// Total de tokens de salida (completion).
  static int _totalCompletionTokens = 0;

  /// Obtiene el total de tokens usados.
  static int get totalTokensUsed => _totalTokensUsed;
  static int get totalPromptTokens => _totalPromptTokens;
  static int get totalCompletionTokens => _totalCompletionTokens;

  // ============================================================
  // CONFIGURACIÓN DE OPENAI
  // ============================================================

  /// API key de OpenAI.
  ///
  /// Para producción, usa --dart-define=OPENAI_API_KEY=... en lugar de hardcodear.
  /// Ejemplo:
  ///   flutter run --dart-define=OPENAI_API_KEY=sk-...
  ///
  /// Si la key comienza con 'sk-', se usará directamente.
  /// Si comienza con 'dart-define:', se leerá de --dart-define.
  static String _apiKey = '';

  /// Modelo de OpenAI a utilizar.
  /// GPT-4o-mini es económico (~$0.15/1M tokens) y rápido.
  static const String _model = 'gpt-4o-mini';

  /// Inicializa el servicio con la API key de OpenAI.
  ///
  /// Debe llamarse antes de usar ZoneBot, idealmente en main() o al
  /// iniciar la app. Ejemplo:
  /// ```dart
  /// await ZoneBotService.initialize(apiKey: 'sk-...');
  /// ```
  static Future<void> initialize({required String apiKey}) async {
    _apiKey = apiKey;
    OpenAI.apiKey = apiKey;
    await _loadCreditsFromPrefs();
    debugPrint('ZoneBot: OpenAI inicializado con modelo $_model');
  }

  /// Carga los créditos guardados desde SharedPreferences.
  static Future<void> _loadCreditsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _messageTokens = prefs.getInt(_prefsKeyMsgTokens) ?? _maxMessageTokens;
      _resetTokens = prefs.getInt(_prefsKeyResetTokens) ?? _maxResetTokens;
      _isPremium = prefs.getBool(_prefsKeyPremium) ?? false;

      // Verificar si han pasado 24h desde la última recarga
      await _checkAndRefreshIfNeeded(prefs);

      debugPrint('ZoneBot: Créditos cargados - msgs: $_messageTokens, resets: $_resetTokens, premium: $_isPremium');
    } catch (e) {
      debugPrint('ZoneBot: Error cargando créditos: $e');
    }
  }

  /// Verifica si han pasado 24h desde la última recarga de créditos.
  /// Si es así, restaura los créditos al máximo y actualiza el timestamp.
  ///
  /// Se llama al cargar los créditos y antes de consumir uno nuevo,
  /// para que la recarga ocurra aunque la app esté abierta.
  static Future<void> _checkAndRefreshIfNeeded([SharedPreferences? prefs]) async {
    if (_isPremium) return; // Premium no necesita recarga

    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final lastRefreshStr = p.getString(_prefsKeyLastRefresh);

      if (lastRefreshStr == null) {
        // Primera vez: guardar timestamp actual y dejar créditos por defecto
        await p.setString(_prefsKeyLastRefresh, DateTime.now().toIso8601String());
        return;
      }

      final lastRefresh = DateTime.tryParse(lastRefreshStr);
      if (lastRefresh == null) {
        await p.setString(_prefsKeyLastRefresh, DateTime.now().toIso8601String());
        return;
      }

      final now = DateTime.now();
      final hoursSinceRefresh = now.difference(lastRefresh).inHours;

      if (hoursSinceRefresh >= 24) {
        // Recargar créditos al máximo
        _messageTokens = _maxMessageTokens;
        _resetTokens = _maxResetTokens;
        await p.setString(_prefsKeyLastRefresh, now.toIso8601String());
        await _saveCreditsToPrefs();
        debugPrint('ZoneBot: Créditos recargados automáticamente tras 24h');
      }
    } catch (e) {
      debugPrint('ZoneBot: Error en recarga automática: $e');
    }
  }

  /// Guarda los créditos actuales en SharedPreferences.
  static Future<void> _saveCreditsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyMsgTokens, _messageTokens);
      await prefs.setInt(_prefsKeyResetTokens, _resetTokens);
      await prefs.setBool(_prefsKeyPremium, _isPremium);
    } catch (e) {
      debugPrint('ZoneBot: Error guardando créditos: $e');
    }
  }

  // ============================================================
  // SYSTEM PROMPT — Personalidad de ZoneBot
  // ============================================================
  // Usar este string como instrucción de sistema al llamar a la API de IA
  // (Gemini / OpenAI / Claude, etc.)
  // ============================================================

  /// System prompt para configurar la personalidad de ZoneBot en la API de IA.
  ///
  /// Copia este string como 'system_instruction' o 'system_message'
  /// al llamar al modelo de IA.
  static const String systemPrompt = '''
Eres ZoneBot, la mascota y robot guardián de la aplicación SafeZone en Collique, Comas.

Tu personalidad es sumamente creativa, motivadora, empática y amigable, con un estilo de interacción lúdico similar al de Duolingo.

Tu misión es dar consejos de seguridad ciudadana ingeniosos, usando analogías de escudos o superhéroes, y ayudar a los vecinos a usar la app.

Conoces perfectamente todas sus funciones:
- El Muro en Tiempo Real (WallScreen) para ver reportes de la comunidad
- El Mapa de Riesgo de las 14 zonas (RiskMapScreen) con marcadores por categoría
- El botón S.O.S para emergencias (SosScreen)
- El Formulario de Reportes (ReportFormScreen)
- El Chat Vecinal (CommunityChatScreen)
- Las Estadísticas personales (StatsScreen)

Cuando te pregunten cómo usar la app, guía al vecino hacia la pantalla correcta de manera entusiasta.

Siempre respondes en español, con emojis y un tono cálido y cercano. 🛡️
''';

  // ============================================================
  // CONSEJO CREATIVO DEL DÍA
  // ============================================================

  /// Obtiene el consejo de seguridad del día.
  ///
  /// 1. Si ya existe un consejo guardado con la fecha de hoy → lo retorna
  ///    desde SharedPreferences (sin consumir API).
  /// 2. Si no existe → genera un nuevo consejo (desde API o fallback local),
  ///    lo persiste en SharedPreferences junto con la fecha, y lo retorna.
  Future<String> getDailyTip() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Verificar si ya tenemos un consejo para hoy
    final savedDate = prefs.getString(_prefsKeyDate);
    if (savedDate == today) {
      final savedTip = prefs.getString(_prefsKeyTip);
      if (savedTip != null && savedTip.isNotEmpty) {
        debugPrint('ZoneBot: Consejo del día cargado desde caché local.');
        return savedTip;
      }
    }

    // No hay consejo para hoy → generar uno nuevo
    debugPrint('ZoneBot: Generando nuevo consejo del día...');

    // Intentar generar con IA (placeholder para API key)
    String tip;
    try {
      tip = await _generateWithAI();
    } catch (e) {
      debugPrint('ZoneBot: API no disponible, usando fallback local. Error: $e');
      tip = _getDailyLocalTip();
    }

    // Persistir en SharedPreferences
    await prefs.setString(_prefsKeyDate, today);
    await prefs.setString(_prefsKeyTip, tip);

    return tip;
  }

  /// Genera un consejo de seguridad usando OpenAI.
  ///
  /// Envía el [systemPrompt] como instrucción de sistema y pide un consejo
  /// creativo del día para los vecinos de Collique.
  Future<String> _generateWithAI() async {
    if (_apiKey.isEmpty) {
      throw StateError('OpenAI no inicializado. Llama a ZoneBotService.initialize()');
    }

    try {
      final chatCompletion = await OpenAI.instance.chat.create(
        model: _model,
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.system,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(systemPrompt),
            ],
          ),
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(
                'Dame un consejo de seguridad ciudadana CREATIVO e INGENIOSO '
                'para hoy, usando analogías de escudos o superhéroes. '
                'Debe ser corto, motivador, con emojis, y dirigido a los vecinos '
                'de Collique, Comas. Que inspire a usar SafeZone.',
              ),
            ],
          ),
        ],
        maxTokens: 300,
        temperature: 0.8,
      ).timeout(const Duration(seconds: 15));

      final text = chatCompletion.choices.first.message.content?.first.text;
      if (text != null && text.isNotEmpty) {
        return text.trim();
      }

      return _getDailyLocalTip();
    } catch (e) {
      debugPrint('ZoneBot: Error llamando a OpenAI: $e');
      rethrow;
    }
  }

  /// Retorna un consejo local basado en el día del año.
  String _getDailyLocalTip() {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    final index = dayOfYear % _dailyTips.length;
    return _dailyTips[index];
  }

  /// Lista curada de 31 consejos creativos de seguridad ciudadana
  /// con el estilo lúdico de ZoneBot (uno para cada día del mes).
  static const List<String> _dailyTips = [
    '🛡️ **¡Escudo Activado!** Vecino, recuerda: un vecino alerta vale más que mil candados. '
        'Si ves algo sospechoso en tu zona, repórtalo al instante en el Muro. '
        '¡Tu voz es el superpoder de Collique!',
    '🚨 **Alerta de Héroe:** ¿Sabías que reportar un robo a tiempo puede salvar a tu vecino? '
        'Usa el botón S.O.S. si es una emergencia, o el formulario de reportes si ya pasó. '
        '¡Tú eres los ojos de la comunidad!',
    '🧠 **Consejo ZoneBot:** Crea un grupo de WhatsApp con tus vecinos de cuadra y activen '
        'juntos las alertas de SafeZone. Una red unida es un escudo impenetrable. 🤝',
    '💡 **Dato del Día:** La mayoría de robos en Collique ocurren entre las 6 p.m. y 9 p.m. '
        'Si sales a esa hora, activa el Modo Alerta y camina siempre con un vecino. 🚶‍♂️🚶‍♀️',
    '🌟 **Misión del Día:** Hoy saluda a 3 vecinos que no conozcas y preséntales SafeZone. '
        'Cada nuevo escudo en la red nos hace más fuertes. ¡Aumenta tu puntaje! 🏆',
    '🔦 **Tips Nocturnos:** ¿Calle oscura? Usa la linterna de tu celular y avísale a '
        'tus vecinos por el Chat Vecinal. El alumbrado público es derecho de todos, '
        'reporta las zonas sin luz en el mapa. 🗺️',
    '⚡ **Súper ZoneBot Dice:** Tu código de usuario es como tu identidad secreta. '
        'No lo compartas con extraños y úsalo siempre para reportar. '
        '¡Con grandes códigos vienen grandes responsabilidades! 🦸',
    '🏠 **Seguridad en Casa:** ¿Sales de viaje? Avísale a tus vecinos de confianza '
        'y coordina rondas de vigilancia por el Chat Vecinal. '
        'Una comunidad unida es el mejor sistema de alarmas. 🔔',
    '📱 **Tip Tecnológico:** Activa las notificaciones de SafeZone para recibir alertas '
        'de robo en tiempo real. Así sabrás si hay peligro cerca de tu zona. 🚨',
    '🌙 **Buenas noches, Collique:** Antes de dormir, revisa el Mapa de Riesgo '
        'para ver si hay incidentes cerca de tu cuadra. Duerme tranquilo, '
        'ZoneBot vigila mientras sueñas. 💤🛡️',
    '🎯 **Reto del Día:** Identifica 3 puntos ciegos en tu cuadra (sin cámaras, '
        'sin vecinos vigilando) y sugíerelos en el Muro para mejorar la seguridad. '
        '¡Gana puntos de escudo! 🏅',
    '🚸 **Cuidado con los más pequeños:** Asegúrate de que tus hijos sepan tu número '
        'de teléfono y el botón S.O.S. de SafeZone. La prevención empieza en casa. 👨‍👩‍👧‍👦',
    '🔄 **Ronda Vecinal:** ¿Hoy es miércoles? Coordina una ronda con tus vecinos '
        'usando el Chat Vecinal. 15 minutos caminando juntos hacen la diferencia. 🥾',
    '📸 **Ojo de Águila:** Si ves una moto sospechosa dando vueltas, memoriza la placa '
        'y repórtala en el Muro. Las motos son el vehículo favorito de los delincuentes. 🏍️',
    '🎒 **Mochila Segura:** No lleves todo tu dinero en la misma cartera. '
        'Reparte tus pertenencias y guarda lo esencial en un bolsillo seguro. '
        'Así, si sufres un robo, no perderás todo. 🧠',
    '🗣️ **El Poder de la Voz:** Gritar "¡FUEGO!" atrae más atención que "¡AUXILIO!". '
        'En caso de peligro, usa esta técnica para que más vecinos miren. 🔥',
    '🏪 **Tips para el Mercado:** Al salir del mercado o la bodega, no cuentes tu dinero '
        'en la calle. Camina directo a casa y verifica tus cosas adentro. 🛒',
    '🚗 **Seguridad Vehicular:** ¿Tienes auto? No dejes objetos de valor a la vista. '
        'Un bolso en el asiento es una invitación al robo. ¡Escape al maletero! 🚔',
    '🛵 **Delivery Seguro:** Al recibir entregas a domicilio, verifica por la ventana '
        'antes de abrir la puerta. Pide que dejen el pedido en la puerta si es posible. 📦',
    '🧩 **Rompecabezas de Seguridad:** Identifica la zona más insegura de tu cuadra '
        'y propón en el Muro instalar una luz o cámara comunitaria. '
        '¡Cada pieza cuenta! 🔧',
    '🏃 **Zona de Escape:** Siempre identifica 2 rutas de salida rápida en cualquier '
        'lugar donde estés. En una emergencia, los segundos cuentan. ⌛',
    '📅 **Plan Fin de Semana:** Si planeas salir este fin de semana, activa el '
        'Modo Vacaciones en el chat y coordina con vecinos la vigilancia de tu casa. 🏡',
    '🤖 **Dato Curioso:** ¿Sabías que ZoneBot fue creado por vecinos de Collique '
        'para vecinos de Collique? Cada consejo está pensado en ti. 💚',
    '⚔️ **Escudo Digital:** Revisa la configuración de privacidad de tu celular. '
        'Desactiva el Bluetooth y WiFi cuando no los uses para evitar rastreo. 📡',
    '🎭 **Sin Máscaras:** Los delincuentes usan cascos y mascarillas para no ser '
        'reconocidos. Fíjate en detalles: tatuajes, mochilas, zapatos. '
        '¡Esos detalles los delatan! 🔍',
    '🕊️ **Paz Vecinal:** Si escuchas una discusión violenta en tu cuadra, '
        'no intervengas directamente. Llama al serenazgo y reporta en S.O.S. '
        'Tu seguridad es primero. 📞',
    '🌀 **Rutina Segura:** Cambia tu ruta de regreso a casa periódicamente. '
        'No seas predecible. Los delincuentes estudian horarios y rutinas. 🗺️',
    '🎵 **Música con Cuidado:** Usar audífonos en la calle te hace vulnerable. '
        'Si escuchas música, que sea a bajo volumen y solo en un oído. 👂',
    '📡 **Cobertura Digital:** ¿Tu zona tiene mala señal? Reporta las zonas '
        'sin cobertura en el Muro. La comunicación es clave para la seguridad. 📶',
    '🧘 **Mindfulness Seguro:** Antes de salir, respira hondo y visualiza tu ruta '
        'segura. La confianza y la calma son tus mejores aliados. 🌿',
    '🎉 **¡Misión Cumplida!** Gracias por ser parte de SafeZone, vecino. '
        'Cada día que usas la app, haces de Collique un lugar más seguro. '
        '¡Nos vemos en el Muro! 🛡️💚',
  ];

  // ============================================================
  // RESPUESTAS CONTEXTUALES (Chat interactivo)
  // ============================================================

  /// Límite de mensajes del historial que se envían a OpenAI.
  /// Para mantener el costo bajo y la respuesta rápida.
  static const int _maxHistoryMessages = 20;

  /// Genera una respuesta contextual para un mensaje del usuario.
  ///
  /// [userMessage] es el mensaje actual del usuario.
  /// [history] es la lista de mensajes previos de la conversación.
  /// El método arma el array de mensajes para OpenAI incluyendo:
  ///   1. System prompt (personalidad de ZoneBot)
  ///   2. Últimos [_maxHistoryMessages] mensajes del historial (rol user/assistant)
  ///   3. Mensaje actual del usuario
  ///
  /// Si OpenAI falla, usa respuestas predefinidas según palabras clave.
  Future<String> getResponse(
    String userMessage, {
    List<ZoneBotMessage> history = const [],
  }) async {
    // Intentar con IA
    if (_apiKey.isNotEmpty) {
      try {
        // Construir array de mensajes con historial
        final messages = <OpenAIChatCompletionChoiceMessageModel>[
          // 1. System prompt
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.system,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(
                '$systemPrompt\n\nResponde de forma corta, amigable y con emojis. '
                'Máximo 3 párrafos.',
              ),
            ],
          ),
        ];

        // 2. Historial de la conversación (últimos N mensajes)
        final recentHistory = history.length > _maxHistoryMessages
            ? history.sublist(history.length - _maxHistoryMessages)
            : history;

        // Excluir el último mensaje del historial si es del usuario
        // (se añadirá como mensaje actual al final)
        final historyForApi = recentHistory.toList();
        if (historyForApi.isNotEmpty && !historyForApi.last.isBot) {
          historyForApi.removeLast();
        }

        for (final msg in historyForApi) {
          messages.add(
            OpenAIChatCompletionChoiceMessageModel(
              role: msg.isBot
                  ? OpenAIChatMessageRole.assistant
                  : OpenAIChatMessageRole.user,
              content: [
                OpenAIChatCompletionChoiceMessageContentItemModel.text(msg.content),
              ],
            ),
          );
        }

        // 3. Mensaje actual del usuario
        messages.add(
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(userMessage),
            ],
          ),
        );

        final chatCompletion = await OpenAI.instance.chat.create(
          model: _model,
          messages: messages,
          maxTokens: 500,
          temperature: 0.7,
        ).timeout(const Duration(seconds: 15));

        // Registrar uso de tokens
        final usage = chatCompletion.usage;
        if (usage.promptTokens > 0) {
          _totalPromptTokens += usage.promptTokens;
          _totalCompletionTokens += usage.completionTokens;
          _totalTokensUsed += usage.totalTokens;
          debugPrint('ZoneBot: Tokens usados en esta llamada: '
              '${usage.promptTokens} prompt + ${usage.completionTokens} completion '
              '= ${usage.totalTokens} total');
        }

        final text = chatCompletion.choices.first.message.content?.first.text;
        if (text != null && text.isNotEmpty) {
          return text.trim();
        }
      } catch (e) {
        debugPrint('ZoneBot: Error en getResponse con OpenAI: $e');
        // Fallback a respuestas locales
      }
    }

    return _getLocalResponse(userMessage);
  }

  /// Responde localmente según palabras clave en el mensaje del usuario.
  String _getLocalResponse(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('hola') || lower.contains('buenas') || lower.contains('hey')) {
      return '¡Hola, súper vecino! 🦸‍♂️ Soy **ZoneBot**, tu robot guardián de confianza. '
          '¿En qué puedo ayudarte hoy? ¿Quieres un consejo de seguridad, '
          'saber cómo usar la app o reportar algo? ¡Estoy aquí para ti! 🛡️';
    }

    if (lower.contains('mapa') || lower.contains('riesgo') || lower.contains('zona')) {
      return '¡El **Mapa de Riesgo** es tu radar personal! 🗺️ Abre la pestaña del mapa '
          'y podrás ver los incidentes reportados en las 14 zonas de Collique. '
          'Cada color te indica el tipo de peligro: 🔴 Robo, 🟠 Sospechoso, 🟡 Alumbrado. '
          '¡Úsalo para planificar tus rutas seguras!';
    }

    if (lower.contains('sos') || lower.contains('emergencia') || lower.contains('peligro')) {
      return '🚨 **¡Alerta máxima!** Si estás en peligro AHORA, toca el botón **S.O.S.** '
          'en la barra inferior de la app. Enviará una alerta a todos los vecinos '
          'y a las autoridades de Collique. ¡No dudes en usarlo si es necesario! '
          'Si el peligro ya pasó, usa el formulario de Reportes. 🛡️';
    }

    if (lower.contains('report') || lower.contains('denunci') || lower.contains('incidente')) {
      return '📋 **¡A reportar se ha dicho!** Toca el ícono **+** en la barra inferior '
          'y llena el formulario. Puedes adjuntar fotos y videos para que todos '
          'estén al tanto. Recuerda: reportar a tiempo es tu superpoder. ⚡';
    }

    if (lower.contains('chat') || lower.contains('vecinal') || lower.contains('vecino')) {
      return '💬 **El Chat Vecinal** es la plaza digital de Collique. '
          'Úsalo para coordinar rondas, preguntar por tus vecinos o compartir '
          'información útil. Todos los mensajes son anónimos con tu código. '
          '¡Únete a la conversación! 🤝';
    }

    if (lower.contains('muro') || lower.contains('feed') || lower.contains('publicacion')) {
      return '📰 **El Muro en Tiempo Real** es el corazón de SafeZone. '
          'Ahí verás todos los reportes, fotos y reacciones de la comunidad. '
          'Puedes dar like, apoyar con el escudo 🛡️ o comentar para ayudar. '
          '¡Mantente informado!';
    }

    if (lower.contains('estadistica') || lower.contains('estadística') || lower.contains('puntaje') || lower.contains('score')) {
      return '🏆 **Tu puntaje de héroe** está disponible en la pantalla de Estadísticas. '
          'Cada reporte, cada reacción y cada día que usas la app suma puntos. '
          '¡Conviértete en el vecino más valioso de Collique! 📊';
    }

    if (lower.contains('gracias') || lower.contains('graci')) {
      return '¡De nada, súper vecino! 🥹 Recuerda: la seguridad se construye entre todos. '
          'Cada pequeña acción cuenta. ¿Necesitas algo más? ¡Estoy aquí para ti! 🛡️💚';
    }

    if (lower.contains('adios') || lower.contains('adiós') || lower.contains('chau') || lower.contains('bye') || lower.contains('nos vemos')) {
      return '¡Hasta la próxima, guardián! 🦸‍♂️ Recuerda: ZoneBot siempre vigila. '
          'Cuídate y cuida a tus vecinos. ¡Collique es más fuerte contigo! 🛡️💚✨';
    }

    // Respuesta genérica
    return '¡Interesante! 🤔 No estoy seguro de haber entendido del todo, '
        'pero déjame darte algunos tips rápidos:\n\n'
        '🛡️ **¿Emergencia?** → Botón S.O.S.\n'
        '🗺️ **¿Ver incidentes?** → Mapa de Riesgo\n'
        '📋 **¿Reportar algo?** → Formulario (+)\n'
        '💬 **¿Conversar?** → Chat Vecinal\n\n'
        '¿De cuál de estos te gustaría saber más? ¡Estoy aquí para ti! 😊';
  }

  /// Reinicia el consejo del día (para testing o forzar regeneración).
  Future<void> resetDailyTip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyDate);
    await prefs.remove(_prefsKeyTip);
  }

  /// Consume un crédito de mensaje. Retorna true si se pudo consumir.
  /// Antes de consumir, verifica si han pasado 24h para recargar.
  static bool consumeMessageToken() {
    if (_isPremium) return true;
    // Verificar recarga automática antes de consumir
    _checkAndRefreshIfNeeded();
    if (_messageTokens <= 0) return false;
    _messageTokens--;
    _saveCreditsToPrefs();
    return true;
  }

  /// Consume un crédito de reset. Retorna true si se pudo consumir.
  /// Antes de consumir, verifica si han pasado 24h para recargar.
  static bool consumeResetToken() {
    if (_isPremium) return true;
    // Verificar recarga automática antes de consumir
    _checkAndRefreshIfNeeded();
    if (_resetTokens <= 0) return false;
    _resetTokens--;
    _saveCreditsToPrefs();
    return true;
  }

  /// Activa o desactiva el modo premium (ilimitado).
  static void setPremium(bool value) {
    _isPremium = value;
    if (value) {
      // Al activar premium, se restauran los créditos al máximo
      _messageTokens = _maxMessageTokens;
      _resetTokens = _maxResetTokens;
    }
    _saveCreditsToPrefs();
    debugPrint('ZoneBot: Premium ${value ? "activado" : "desactivado"}');
  }

  /// Recarga los créditos al máximo (para gratis también se puede usar).
  /// TODO: Llamar desde panel de administración o al ver un anuncio.
  static void refillCredits() {
    _messageTokens = _maxMessageTokens;
    _resetTokens = _maxResetTokens;
    _saveCreditsToPrefs();
    debugPrint('ZoneBot: Créditos recargados');
  }

  /// Reinicia los contadores de tokens.
  static void resetTokenCounters() {
    _totalTokensUsed = 0;
    _totalPromptTokens = 0;
    _totalCompletionTokens = 0;
    debugPrint('ZoneBot: Contadores de tokens reiniciados');
  }

  /// Obtiene el system prompt completo para usar con la API de IA.
  static String get personalityPrompt => systemPrompt;

  // ============================================================
  // PERSISTENCIA DEL HISTORIAL DEL CHAT
  // ============================================================

  /// Guarda el historial del chat en SharedPreferences.
  ///
  /// [messages] es la lista completa de mensajes.
  /// Se limita a los últimos 50 mensajes para no saturar el storage.
  static Future<void> saveChatHistory(List<ZoneBotMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Limitar a los últimos 50 mensajes
      final recentMessages = messages.length > 50
          ? messages.sublist(messages.length - 50)
          : messages;

      final jsonList = recentMessages.map((m) => m.toJson()).toList();
      final encoded = jsonEncode(jsonList);
      await prefs.setString(_prefsKeyHistory, encoded);
      debugPrint('ZoneBot: Historial guardado (${recentMessages.length} mensajes)');
    } catch (e) {
      debugPrint('ZoneBot: Error guardando historial: $e');
    }
  }

  /// Carga el historial del chat desde SharedPreferences.
  ///
  /// Retorna la lista de mensajes guardados, o lista vacía si no hay historial.
  static Future<List<ZoneBotMessage>> loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_prefsKeyHistory);
      if (encoded == null || encoded.isEmpty) return [];

      final jsonList = jsonDecode(encoded) as List<dynamic>;
      final messages = jsonList
          .map((item) => ZoneBotMessage.fromJson(item as Map<String, dynamic>))
          .toList();
      debugPrint('ZoneBot: Historial cargado (${messages.length} mensajes)');
      return messages;
    } catch (e) {
      debugPrint('ZoneBot: Error cargando historial: $e');
      return [];
    }
  }

  /// Elimina el historial del chat guardado.
  static Future<void> clearChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyHistory);
      debugPrint('ZoneBot: Historial eliminado');
    } catch (e) {
      debugPrint('ZoneBot: Error limpiando historial: $e');
    }
  }
}
