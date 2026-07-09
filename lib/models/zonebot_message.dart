/// Modelo para los mensajes del chat de ZoneBot.
///
/// Distingue entre mensajes del usuario y del bot,
/// e incluye soporte para estados de animación del bot.
class ZoneBotMessage {
  final String id;
  final String content;
  final bool isBot;
  final DateTime createdAt;

  /// Estado de animación del bot en el momento de este mensaje:
  /// 'idle', 'thinking', 'happy'
  final String botAnimationState;

  ZoneBotMessage({
    required this.id,
    required this.content,
    required this.isBot,
    required this.createdAt,
    this.botAnimationState = 'idle',
  });

  /// Crea un mensaje del bot (ZoneBot).
  factory ZoneBotMessage.bot({
    required String id,
    required String content,
    required DateTime createdAt,
    String botAnimationState = 'idle',
  }) {
    return ZoneBotMessage(
      id: id,
      content: content,
      isBot: true,
      createdAt: createdAt,
      botAnimationState: botAnimationState,
    );
  }

  /// Crea un mensaje del usuario.
  factory ZoneBotMessage.user({
    required String id,
    required String content,
    required DateTime createdAt,
  }) {
    return ZoneBotMessage(
      id: id,
      content: content,
      isBot: false,
      createdAt: createdAt,
    );
  }

  // ============================================================
  // SERIALIZACIÓN JSON (para SharedPreferences)
  // ============================================================

  /// Convierte el mensaje a un Map para serialización JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'isBot': isBot,
      'createdAt': createdAt.toIso8601String(),
      'botAnimationState': botAnimationState,
    };
  }

  /// Crea un mensaje desde un Map (deserialización JSON).
  factory ZoneBotMessage.fromJson(Map<String, dynamic> json) {
    return ZoneBotMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      isBot: json['isBot'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      botAnimationState: json['botAnimationState'] as String? ?? 'idle',
    );
  }
}
