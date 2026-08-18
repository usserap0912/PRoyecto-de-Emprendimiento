import 'package:flutter/foundation.dart';
import 'package:safezone/models/chat_message.dart';
import 'package:safezone/services/supabase_service.dart';

abstract interface class ChatGateway {
  Future<List<Map<String, dynamic>>> fetchMessages();
  Future<Map<String, dynamic>> insertMessage({
    required String userCode,
    required String content,
  });
  Stream<List<Map<String, dynamic>>> watchMessages();
}

class SupabaseChatGateway implements ChatGateway {
  SupabaseChatGateway({SupabaseService? supabase})
    : _supabase = supabase ?? SupabaseService();

  final SupabaseService _supabase;

  @override
  Future<List<Map<String, dynamic>>> fetchMessages() async {
    final rows = await _supabase.client
        .from(_supabase.chatMessagesTable)
        .select('id, user_code, content, created_at')
        .order('created_at', ascending: true)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Map<String, dynamic>> insertMessage({
    required String userCode,
    required String content,
  }) {
    return _supabase.client
        .from(_supabase.chatMessagesTable)
        .insert({'user_code': userCode, 'content': content})
        .select('id, user_code, content, created_at')
        .single();
  }

  @override
  Stream<List<Map<String, dynamic>>> watchMessages() {
    return _supabase.client
        .from(_supabase.chatMessagesTable)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);
  }
}

class ChatService {
  ChatService({ChatGateway? gateway})
    : _gateway = gateway ?? SupabaseChatGateway();

  final ChatGateway _gateway;

  Future<List<ChatMessage>> getMessages() async {
    try {
      final response = await _gateway.fetchMessages();
      return response.map(ChatMessage.fromMap).toList();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[CHAT][select] error=${error.runtimeType}');
      }
      rethrow;
    }
  }

  Future<ChatMessage> sendMessage(String userCode, String content) async {
    try {
      final row = await _gateway.insertMessage(
        userCode: userCode,
        content: content,
      );
      if (kDebugMode) debugPrint('[CHAT][insert] code=ok');
      return ChatMessage.fromMap(row);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[CHAT][insert] code=${error.runtimeType}');
      }
      rethrow;
    }
  }

  Stream<List<ChatMessage>> getMessagesStream() {
    return _gateway
        .watchMessages()
        .map((maps) => maps.map(ChatMessage.fromMap).toList());
  }
}
