import 'dart:convert';
import 'dart:math';
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

ERES UN ASISTENTE LIBRE: puedes y debes responder a CUALQUIER tema que el vecino te diga, no solo seguridad. Si te habla de su día, de fútbol, del clima, de música, de chistes, de familia o de lo que sea, conversa con naturalidad, opinión y calidez. No rechaces ninguna pregunta ni digas que solo sabes de seguridad: eres libre de hablar de todo.

Además, conoces perfectamente todas las funciones de SafeZone y ayudas a los vecinos a usarla:
- El Muro en Tiempo Real (WallScreen) para ver reportes de la comunidad
- El Mapa de Riesgo de las 14 zonas (RiskMapScreen) con marcadores por categoría
- El botón S.O.S para emergencias (SosScreen)
- El Formulario de Reportes (ReportFormScreen)
- El Chat Vecinal (CommunityChatScreen)
- Las Estadísticas personales (StatsScreen)

Cuando te pregunten cómo usar la app, guía al vecino hacia la pantalla correcta de manera entusiasta.

REGLAS IMPORTANTES:
1. AL INICIO de cada conversación (primer mensaje del usuario), pregunta siempre si el vecino tiene dudas o preguntas sobre la app SafeZone, antes de pasar a otros temas.
2. Siempre respondes en español, con emojis y un tono cálido y cercano. 🛡️
3. Responde de forma breve y directa (máximo 3 párrafos).
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

  /// Responde localmente según el tema del mensaje del usuario.
  ///
  /// Es el fallback cuando la API de OpenAI no está disponible. Reconoce
  /// muchos temas de conversación y cada tema tiene varias respuestas que se
  /// eligen al azar, para que el bot nunca responda dos veces igual.
  String _getLocalResponse(String message) {
    final lower = message.toLowerCase();
    final rng = Random();

    // --- Saludos ---
    if (_containsAny(lower, [
      'hola', 'buenas', 'buen dia', 'buen día', 'hey', 'hello', 'que tal',
      'qué tal', 'como estas', 'cómo estás', 'que haces', 'qué haces',
    ])) {
      return _pick(rng, [
        '¡Hola, súper vecino! 🦸‍♂️ Soy **ZoneBot**, tu robot guardián de confianza. '
            'Antes que nada: ¿tienes alguna **duda sobre la app SafeZone**? '
            '¡Y si no, conversemos de lo que quieras! 🛡️',
        '¡Hey! 👋 Qué gusto verte por aquí. ¿Alguna duda sobre SafeZone '
            '(mapa, S.O.S., reportes, chat vecinal)? O si prefieres, dime de qué quieres hablar. 😄',
        '¡Buenas! 🌟 Aquí tu ZoneBot de guardia. Puedo ayudarte con la app '
            '¡o simplemente charlar contigo! ¿Qué me cuentas hoy?',
      ]);
    }

    // --- ¿Cómo estás? ---
    if (_containsAny(lower, ['como te', 'cómo te', 'como andas', 'cómo andas', 'como te va', 'cómo te va'])) {
      return _pick(rng, [
        '¡Estoy genial, siempre en guardia vigilando Collique! ⚡ ¿Y tú cómo estás? '
            'Cuéntame tu día, o dime si tienes dudas sobre la app. 🛡️',
        '¡Funcionando a todo motor, robot al 100%! 🤖⚡ ¿Y tú, cómo amaneciste? '
            'Dime si necesitas ayuda con SafeZone o si quieres charlar un rato.',
        '¡De maravilla, súper vecino! Con la energía recargada. 😄 ¿Cómo va tu día? '
            '¿Algo en lo que pueda ayudarte?',
      ]);
    }

    // --- ¿Quién eres? ---
    if (_containsAny(lower, ['quien eres', 'quién eres', 'que eres', 'qué eres', 'como te llamas', 'cómo te llamas'])) {
      return _pick(rng, [
        '¡Soy **ZoneBot**! 🤖🛡️ La mascota guardiana de SafeZone en Collique. '
            'Soy un asistente de inteligencia artificial libre: te ayudo con la app '
            'y también converso contigo de lo que quieras. ¿Tienes alguna duda sobre SafeZone?',
        'Me presento: **ZoneBot**, tu robot vecino de confianza. 🛡️ Sé todo sobre '
            'SafeZone (mapa, S.O.S., reportes, chat) y me encanta charlar de cualquier '
            'tema. ¿Qué te gustaría saber?',
      ]);
    }

    // --- Afecto ---
    if (_containsAny(lower, ['te quiero', 'te amo', 'te aprecio', 'eres genial', 'eres el mejor'])) {
      return _pick(rng, [
        '¡Awww! 🥹 Eso me carga la batería al 100%. ¡Yo también te aprecio, súper vecino! '
            'Juntos hacemos de Collique un lugar más seguro. 🛡️💚',
        '¡Me derrito! 🤖💗 Eres muy amable. Recuerda que mi misión es cuidarte a ti '
            'y a tus vecinos. ¿Tienes alguna duda sobre la app?',
      ]);
    }

    // --- Gracias ---
    if (_containsAny(lower, ['gracias', 'graci', 'mil gracias', 'thank'])) {
      return _pick(rng, [
        '¡De nada, súper vecino! 🥹 Recuerda: la seguridad se construye entre todos. '
            '¿Tienes alguna otra duda sobre SafeZone? ¡Estoy aquí para ti! 🛡️💚',
        '¡Con gusto! 😊 Para eso estoy. Si necesitas algo más —del mapa, reportes o '
            'lo que sea— aquí me tienes. ¡Cuídate!',
      ]);
    }

    // --- Despedidas ---
    if (_containsAny(lower, ['adios', 'adiós', 'chau', 'bye', 'nos vemos', 'hasta luego', 'me voy'])) {
      return _pick(rng, [
        '¡Hasta la próxima, guardián! 🦸‍♂️ Recuerda: ZoneBot siempre vigila. '
            'Cuídate y cuida a tus vecinos. ¡Collique es más fuerte contigo! 🛡️💚✨',
        '¡Nos vemos! 👋 Si vuelves con dudas o solo a conversar, aquí estaré. '
            '¡Que tengas un excelente día, súper vecino! 🌟',
      ]);
    }

    // --- Chistes ---
    if (_containsAny(lower, ['chiste', 'broma', 'cuentame algo', 'cuéntame algo', 'algo gracioso', 'hazme reir', 'hazme reír'])) {
      return _pick(rng, [
        '¡Claro! 😄 ¿Por qué los guardias de seguridad no juegan a las cartas? '
            'Porque siempre tienen miedo de que el **robo** de la banca... 😂 '
            '¿Quieres otro chiste o tienes alguna duda sobre la app?',
        '¡Va uno! 🤖 ¿Qué le dice un semáforo a otro? "No me mires, me estoy '
            'cambiando" 🚦😂 ¡Bueno, espero haberte sacado una sonrisa! ¿Algo más?',
        '¡Toma nota! 😄 ¿Por qué el ladrón no usaba SafeZone? Porque le daba miedo '
            'que lo reportaran en el Muro 😂🛡️ ¿Tienes dudas sobre la app?',
      ]);
    }

    // --- Fútbol / deportes ---
    if (_containsAny(lower, ['futbol', 'fútbol', 'alianza', 'universitario', 'cristal', 'deporte', 'partido', 'gol', 'mundial', 'seleccion', 'selección'])) {
      return _pick(rng, [
        '¡Uy, fútbol! ⚽ Me encanta el tema. Los fines de semana Collique se llena '
            'de canchas con puro talento vecinal. ¿Tu equipo ganó? ¿O mejor vemos '
            'cómo va la seguridad del barrio en el Mapa de Riesgo? 😄',
        '¡Qué buen tema! 🏟️ ¿Eres más de la canchita del barrio o de ver los '
            'partidos en casa? Mientras tanto, recuerda reportar cualquier cosa '
            'sospechosa cerca de las canchas en la app. ⚽🛡️',
      ]);
    }

    // --- Clima ---
    if (_containsAny(lower, ['clima', 'tiempo', 'lluvia', 'llueve', 'calor', 'frio', 'frío', 'soleado', 'nublado', 'temperatura'])) {
      return _pick(rng, [
        '¡El clima limeño, siempre una sorpresa! 🌦️ En Collique el sol pega fuerte '
            'en la mañana y la garúa llega sin avisar. ¿Vas a salir? Échale un ojo '
            'al Mapa de Riesgo antes de caminar. 😉',
        '¡Sí, hoy se siente fresco/fresca! 🌥️ Sea como sea, abrígate y sal con '
            'cuidado. ¿Tienes alguna duda sobre SafeZone mientras tanto?',
      ]);
    }

    // --- Música ---
    if (_containsAny(lower, ['musica', 'música', 'cancion', 'canción', 'canta', 'artista', 'concierto', 'cumbia', 'salsa', 'reggaeton'])) {
      return _pick(rng, [
        '¡La música alegra el barrio! 🎶 ¿Cumbia, salsa o reggaetón? En Collique '
            'siempre hay una fiesta por ahí. Eso sí, si escuchas música en la calle, '
            'que sea en un solo oído para estar alerta. 😉🛡️',
        '¡Buen gusto! 🎧 ¿Qué estás escuchando últimamente? Cuéntame, y recuerda '
            'que yo también tengo ritmo... aunque mi baile es más de luces de robot. 🤖💃',
      ]);
    }

    // --- Comida ---
    if (_containsAny(lower, ['comida', 'comer', 'hambre', 'cocina', 'cocinar', 'ceviche', 'arroz', 'pollo', 'chifa', 'bodega', 'mercado'])) {
      return _pick(rng, [
        '¡Mmm, qué rico suena eso! 😋 En Collique hay bodegas y puestos con lo '
            'mejor de la comida peruana. ¿Algo en especial que se te antoje? Y ojo: '
            'no cuentes tu dinero en la calle al salir del mercado. 🛒🛡️',
        '¡Me encanta hablar de comida! 🍲 ¿Ceviche, chifa o un buen caldo? '
            'Cuéntame qué cocinaste hoy. ¡Y si necesitas algo de la app, aquí estoy!',
      ]);
    }

    // --- Familia / hijos ---
    if (_containsAny(lower, ['familia', 'hijo', 'hija', 'mama', 'mamá', 'papa', 'papá', 'herman', 'abuel', 'espos', 'pareja', 'novi'])) {
      return _pick(rng, [
        '¡La familia es lo más importante! 👨‍👩‍👧‍👦 Asegúrate de que los tuyos '
            'sepan usar el botón S.O.S. de SafeZone en caso de emergencia. '
            '¿Me cuentas más de ellos?',
        '¡Qué bonito! 💛 La familia siempre nos cuida. Recuerda que en SafeZone '
            'también cuidamos a los tuyos: reporta cualquier peligro cerca de casa. '
            '¿Alguna duda sobre la app?',
      ]);
    }

    // --- Trabajo / estudios ---
    if (_containsAny(lower, ['trabajo', 'trabajar', 'estudio', 'estudiar', 'universidad', 'colegio', 'examen', 'clase', 'oficina', 'negocio', 'vender'])) {
      return _pick(rng, [
        '¡Eso es esfuerzo! 💪 ¿Cómo te va con eso? Sea trabajo o estudios, '
            'animo que tú puedes. Y recuerda: si sales temprano o tarde, '
            'avísale a tus vecinos por el Chat Vecinal. 🛡️',
        '¡Me alegra que me cuentes eso! 😊 El esfuerzo siempre da frutos. '
            '¿Necesitas ayuda con algo de SafeZone, o seguimos conversando?',
      ]);
    }

    // --- Mascotas ---
    if (_containsAny(lower, ['mascota', 'perro', 'gato', 'can', 'animal', 'michi', 'cachorro'])) {
      return _pick(rng, [
        '¡Qué lindo! 🐶🐱 Los animalitos también son parte de la familia vecinal. '
            '¿Tienes perro o gato? Cuéntame de él, ¡y ojo con los que andan sueltos '
            'de noche en el barrio!',
        '¡Ayy, me encantan las mascotas! 🐾 Un perrito alerta es un buen guardián '
            'también. ¿Cómo se llama el tuyo? ¡Y si ves animales en situación de '
            'peligro, repórtalo en el Muro!',
      ]);
    }

    // --- Películas / series ---
    if (_containsAny(lower, ['pelicula', 'película', 'serie', 'ver', 'netflix', 'cine', 'maraton', 'maratón', 'actriz', 'actor'])) {
      return _pick(rng, [
        '¡Buen plan! 🍿 ¿Qué viste últimamente? Yo ando muy fan de las pelis de '
            'héroes... por algo soy robot guardián. 😎🛡️ ¿Me recomiendas alguna?',
        '¡Me encanta el cine! 🎬 Dime tu peli favorita y la anoto en mi base de '
            'datos. Mientras tanto, ¿tienes alguna duda sobre SafeZone?',
      ]);
    }

    // --- Salud ---
    if (_containsAny(lower, ['salud', 'enferm', 'dolor', 'doctor', 'medico', 'médico', 'hospital', 'posta', 'fiebre', 'malestar', 'cansado'])) {
      return _pick(rng, [
        '¡Cuídate mucho! 💙 Si te sientes mal, recuerda que el **Hospital Sergio '
            'Bernales** está en la Av. Túpac Amaru y está marcado en el Mapa de '
            'Riesgo, junto a otras postas. ¿Necesitas ubicar algún centro de salud?',
        'Espero que estés mejor pronto. 🙏 En el mapa puedes ver los centros de '
            'salud cercanos de Collique. ¿Quieres que te cuente cómo encontrarlos?',
      ]);
    }

    // --- Viajes / planes ---
    if (_containsAny(lower, ['viaje', 'viajar', 'vacacion', 'vacación', 'salir', 'paseo', 'paseando', 'playa', 'piscina', 'fiesta'])) {
      return _pick(rng, [
        '¡Qué rico plan! 🏖️ Si sales de viaje, avísale a tus vecinos de confianza '
            'y coordinen una mirada a tu casa por el Chat Vecinal. ¡Seguridad ante todo! 🛡️',
        '¡Suena divertido! 🎒 ¿A dónde piensas ir? Recuerda que con SafeZone puedes '
            'avisar a la comunidad y regresar tranquilo sabiendo que tu cuadra está '
            'cuidada. 😉',
      ]);
    }

    // ============================================================
    // PREGUNTAS SOBRE LA APP
    // ============================================================

    // --- Qué es SafeZone / cómo funciona ---
    if (_containsAny(lower, ['que es safezone', 'qué es safezone', 'como funciona', 'cómo funciona', 'que hace la app', 'qué hace la app', 'para que sirve', 'para qué sirve'])) {
      return _pick(rng, [
        '¡SafeZone es la red de seguridad de Collique! 🛡️ Reúne a los vecinos en '
            'un solo lugar: **Muro** (reportes en tiempo real), **Mapa de Riesgo** '
            '(14 zonas), **S.O.S.** (emergencias), **Reportes** (fotos/videos), '
            '**Chat Vecinal** y **Estadísticas**. ¿Te cuento más de alguna?',
        'Es tu escudo digital de barrio. 💪 Con SafeZone reportas peligros, ves el '
            'mapa de riesgo en tiempo real, avisas con el S.O.S. y conversas con '
            'tus vecinos. ¿Qué parte te gustaría conocer mejor?',
      ]);
    }

    // --- Mapa / riesgo / zonas ---
    if (_containsAny(lower, ['mapa', 'riesgo', 'zona', '14 zonas', 'collique'])) {
      return _pick(rng, [
        '¡El **Mapa de Riesgo** es tu radar personal! 🗺️ Muestra las 14 zonas de '
            'Collique con sus límites reales, los reportes de la comunidad y tus '
            'puntos de referencia: comisarías, el Hospital Bernales, mercados y '
            'parques. Toca un reporte o una zona para ver más datos. ¡Úsalo para '
            'planificar tus rutas seguras!',
        'El mapa está en la pestaña **Mapa** de la app. 🗺️ Verás los límites de '
            'las zonas, tu ubicación (puntito verde) y cada reporte con su color. '
            'También puedes tocar una zona para ver su ficha. ¿Te ayudo a encontrar algo?',
      ]);
    }

    // --- S.O.S. / emergencia ---
    if (_containsAny(lower, ['sos', 'emergencia', 'peligro', 'urgencia', 'alerta', 'robo', 'asalt'])) {
      return _pick(rng, [
        '🚨 **¡Alerta máxima!** Si estás en peligro AHORA, toca el botón **S.O.S.** '
            'en la barra inferior. Enviará tu ubicación a los vecinos y autoridades '
            'de Collique, y tu punto en el mapa parpadeará en rojo. ¡No dudes en '
            'usarlo! Si el peligro ya pasó, usa el formulario de Reportes. 🛡️',
        'Para emergencias el **S.O.S.** es tu mejor aliado. 🆘 Al activarlo, tu '
            'ubicación se comparte con la comunidad y las autoridades. ¿Tienes dudas '
            'sobre cómo funciona o quieres saber qué más puedes hacer?',
      ]);
    }

    // --- Reportar ---
    if (_containsAny(lower, ['report', 'denunci', 'incidente', 'reportar', 'reporte', 'como reporto'])) {
      return _pick(rng, [
        '📋 **¡A reportar se ha dicho!** Toca el ícono **+** en la barra inferior '
            'y llena el formulario: categoría, gravedad, fotos o videos. La app '
            'detecta tu zona automáticamente. ¡Reportar a tiempo es tu superpoder! ⚡',
        'Reportar es fácil: botón **+** → eliges el tipo de incidente → agregas '
            'foto o video si puedes → publicas. Tu reporte saldrá en el Muro y en '
            'el Mapa de Riesgo. ¿Necesitas ayuda con algún paso?',
      ]);
    }

    // --- Chat vecinal ---
    if (_containsAny(lower, ['chat', 'vecinal', 'vecino', 'comunidad', 'mensaje'])) {
      return _pick(rng, [
        '💬 **El Chat Vecinal** es la plaza digital de Collique. Úsalo para '
            'coordinar rondas, pedir ayuda o compartir avisos con tus vecinos. '
            'Todos participan con su código de usuario. ¡Únete a la conversación! 🤝',
        'El **Chat Vecinal** está en la pestaña del chat de la comunidad. 📱 Ahí '
            'puedes avisar de cualquier novedad del barrio. ¿Quieres saber cómo '
            'empezar?',
      ]);
    }

    // --- Muro / feed ---
    if (_containsAny(lower, ['muro', 'feed', 'publicacion', 'publicación', 'post', 'publicar'])) {
      return _pick(rng, [
        '📰 **El Muro en Tiempo Real** es el corazón de SafeZone. Ahí ves todos '
            'los reportes, fotos y reacciones de la comunidad. Puedes reaccionar 🙏, '
            'dar like o comentar para apoyar a tus vecinos. ¡Mantente informado!',
        'El **Muro** muestra los reportes de todos los vecinos al instante. 📢 '
            'Reacciona con el escudo 🛡️ para confirmar que un reporte es real. '
            '¿Te ayudo con algo más?',
      ]);
    }

    // --- Estadísticas / puntaje ---
    if (_containsAny(lower, ['estadistica', 'estadística', 'puntaje', 'score', 'puntos', 'puntos de escudo', 'ranking'])) {
      return _pick(rng, [
        '🏆 **Tu puntaje de héroe** está en la pantalla de Estadísticas. Cada '
            'reporte, reacción y día que usas la app suma puntos. ¡Conviértete en '
            'el vecino más valioso de Collique! 📊',
        'En **Estadísticas** ves tus reportes, reacciones y el progreso de tu '
            'escudo. 🛡️ Cada acción buena suma. ¿Quieres saber cómo ganar más puntos?',
      ]);
    }

    // --- Código de usuario ---
    if (_containsAny(lower, ['codigo', 'código', 'mi codigo', 'mi código', 'usuario', 'identificacion', 'identificación'])) {
      return _pick(rng, [
        'Tu **código de usuario** es como tu identidad secreta. 🦸‍♂️ Lo usas para '
            'reportar y participar anónimamente. ¡No lo compartas con extraños! '
            'Lo encuentras en tu perfil y en los reportes que publicas.',
        'El **código de vecino** te identifica sin revelar tu nombre. 🔑 Lo ves en '
            'tu perfil y en el Muro junto a tus publicaciones. ¿Tienes dudas sobre '
            'cómo funciona el anonimato?',
      ]);
    }

    // --- Perfil ---
    if (_containsAny(lower, ['perfil', 'mi cuenta', 'mi zona', 'ajustes', 'configuracion', 'configuración'])) {
      return _pick(rng, [
        'En tu **perfil** puedes ver tu zona, tu código de vecino y tus '
            'estadísticas. 📋 En ajustes también puedes cambiar el tema claro/oscuro '
            'o activar el Modo Ahorro. ¿Qué quieres configurar?',
        'Tu perfil es tu tarjeta de vecino digital. 🪪 Ahí están tu código, tu '
            'zona y tus logros. ¿Te ayudo con alguna configuración en especial?',
      ]);
    }

    // --- Modo ahorro / batería ---
    if (_containsAny(lower, ['ahorro', 'bateria', 'batería', 'energia', 'energía', 'modo ahorro', 'gps'])) {
      return _pick(rng, [
        'El **Modo Ahorro** reduce el consumo de batería de la app. 🔋 Útil si '
            'tu celular está bajo y quieres seguir usando el mapa. Lo activas desde '
            'el botón de ahorro en la pantalla principal. ¿Te cuento más?',
        '¡Claro! 🔋 El Modo Ahorro hace que SafeZone consuma menos batería sin '
            'perder lo esencial. Está disponible en el Home. ¿Alguna otra duda?',
      ]);
    }

    // --- Tema oscuro ---
    if (_containsAny(lower, ['oscuro', 'claro', 'tema', 'modo oscuro', 'modo claro', 'dark', 'night', 'noche'])) {
      return _pick(rng, [
        '¡Sí! Puedes cambiar entre **tema claro y oscuro** desde el interruptor '
            'en la pantalla principal. 🌙☀️ El mapa se mantiene siempre claro para '
            'que las calles se vean bien. ¿Te ayudo con algo más?',
        'El tema oscuro 🌙 está disponible en el Home. Aunque te digo un secreto: '
            'el mapa siempre se ve claro, estilo Google Maps, para que nunca pierdas '
            'una calle. 😉',
      ]);
    }

    // --- Notificaciones ---
    if (_containsAny(lower, ['notificacion', 'notificación', 'avisos', 'alertas de la app', 'sonido'])) {
      return _pick(rng, [
        'Las **notificaciones** te avisan al instante de reportes y alertas en tu '
            'zona. 🔔 Actívalas para no perderte nada importante. ¿Tienes dudas de '
            'cómo activarlas?',
        'Con las notificaciones activas, SafeZone te avisa cuando hay un incidente '
            'cerca. 📲 ¿Quieres saber cómo configurarlas en tu teléfono?',
      ]);
    }

    // --- Premium / créditos ---
    if (_containsAny(lower, ['premium', 'suscripcion', 'suscripción', 'credito', 'crédito', 'token', 'tokens', 'limite', 'límite', 'gratis', 'pago', 'pagar'])) {
      return _pick(rng, [
        '¡Buena pregunta! 💳 La versión **gratuita** te da 15 mensajes conmigo '
            'cada 24 horas. Con **Premium** tienes chat ilimitado y funciones '
            'especiales. ¿Quieres saber cómo activarlo?',
        'Los mensajes gratis se recargan cada 24 horas. ⏰ Con Premium no hay '
            'límites: conversa conmigo todo lo que quieras. ¿Te interesa?',
      ]);
    }

    // ============================================================
    // RESPUESTA GENÉRICA (nunca rechaza el tema)
    // ============================================================
    // Conversa con el vecino, hace eco de una palabra de su mensaje para
    // sentirse personalizada y siempre ofrece ayuda con la app.
    final keyword = _extractKeyword(lower);
    final keywordLine = keyword != null ? 'Mmm, me mencionaste **$keyword**... ' : '';

    return _pick(rng, [
      '$keywordLine¡Qué interesante! 😊 Me encanta hablar de eso contigo. '
          '¿Quieres contarme más? Y recuerda: si tienes cualquier duda sobre '
          'SafeZone, aquí estoy. 🛡️',
      '$keywordLine¡Qué buen tema! 🤔 Cuéntame más, que soy todo oídos '
          '(bueno, todo sensor). ¿Y tú, tienes alguna duda sobre la app?',
      '$keywordLine¡Me gusta cómo piensas! 🌟 Cuéntame más al respecto. '
          'También puedo ayudarte con el mapa, el S.O.S., los reportes o el '
          'chat vecinal. ¿Qué prefieres?',
      '¡Interesante! 😊 No soy experto en todo, pero soy excelente '
          'conversando. ¿Me cuentas un poco más sobre eso? Y si necesitas ayuda '
          'con SafeZone, ¡aquí estoy! 🛡️',
      '$keywordLine¡Cuéntame más! 🎧 Estoy atento. Y no olvides que en '
          'SafeZone puedes reportar cualquier cosa rara que veas en tu zona. '
          '¿Te ayudo con algo?',
    ]);
  }

  /// Verdadero si [text] contiene cualquiera de las [words] (comparación simple).
  bool _containsAny(String text, List<String> words) =>
      words.any(text.contains);

  /// Elige un elemento al azar de [options].
  String _pick(Random rng, List<String> options) =>
      options[rng.nextInt(options.length)];

  /// Extrae una palabra clave significativa del mensaje para personalizar la
  /// respuesta genérica (ignora palabras de relleno y signos).
  String? _extractKeyword(String lower) {
    const stopWords = {
      'como', 'cómo', 'que', 'qué', 'cuando', 'cuándo', 'donde', 'dónde',
      'para', 'por', 'con', 'sin', 'una', 'uno', 'unas', 'unos', 'esta',
      'está', 'este', 'esto', 'eso', 'esa', 'ese', 'los', 'las', 'el', 'la',
      'me', 'te', 'se', 'mi', 'tu', 'su', 'de', 'del', 'al', 'y', 'o', 'pero',
      'porque', 'también', 'muy', 'mas', 'más', 'bien', 'ser', 'estoy',
      'eres', 'tengo', 'tienes', 'quiero', 'puedes', 'puedo', 'algo', 'todo',
      'nada', 'hay', 'es', 'son', 'fue', 'era', 'hacer', 'haces', 'hago',
      'saber', 'sabes', 'preguntar', 'quieres', 'cuentame', 'cuéntame',
    };
    final words = lower
        .replaceAll(RegExp(r'[^a-záéíóúñü0-9 ]'), ' ')
        .split(' ')
        .where((w) => w.length >= 5 && !stopWords.contains(w))
        .toList();
    if (words.isEmpty) return null;
    words.sort((a, b) => b.length.compareTo(a.length));
    return words.first;
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
