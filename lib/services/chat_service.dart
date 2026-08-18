import 'package:safezone/models/chat_message.dart';
import 'package:safezone/services/supabase_service.dart';

class ChatService {
  final SupabaseService _supabase = SupabaseService();

  /// Obtiene mensajes del chat
  Future<List<ChatMessage>> getMessages() async {
    try {
      final response = await _supabase.client
          .from(_supabase.chatMessagesTable)
          .select()
          .order('created_at', ascending: true)
          .limit(100);

      return (response as List)
          .map((item) => ChatMessage.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return _getSampleMessages();
    }
  }

  /// Envía un mensaje al chat
  Future<void> sendMessage(String userCode, String content) async {
    try {
      await _supabase.client.from(_supabase.chatMessagesTable).insert({
        'content': content,
      });
    } catch (e) {
      // Fallback offline
    }
  }

  /// Escucha mensajes en tiempo real
  Stream<List<ChatMessage>> getMessagesStream() {
    try {
      return _supabase.client
          .from(_supabase.chatMessagesTable)
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: true)
          .map((maps) => maps.map((m) => ChatMessage.fromMap(m)).toList());
    } catch (e) {
      return const Stream.empty();
    }
  }

  List<ChatMessage> _getSampleMessages() {
    return [
      ChatMessage(
        id: 's1',
        userCode: 'User-A7K3',
        content:
            'Buenas noches vecinos, alguien más escuchó ruidos raros en la Av. Revolución?',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      ChatMessage(
        id: 's2',
        userCode: 'User-M9X1',
        content:
            'Sí, yo también. Suena como si estuvieran forcejeando una puerta. 🚨',
        createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      ChatMessage(
        id: 's3',
        userCode: 'User-R4B2',
        content: 'Ya llamé al serenazgo, están en camino. Manténganse alertas.',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ];
  }
}
