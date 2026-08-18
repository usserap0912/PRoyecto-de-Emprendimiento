import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/chat_message.dart';
import 'package:safezone/services/chat_service.dart';

class _FakeChatGateway implements ChatGateway {
  final rows = <Map<String, dynamic>>[];
  final snapshots = StreamController<List<Map<String, dynamic>>>.broadcast();
  Map<String, dynamic>? lastInsert;
  Object? insertError;

  @override
  Future<List<Map<String, dynamic>>> fetchMessages() async => List.of(rows);

  @override
  Future<Map<String, dynamic>> insertMessage({
    required String userCode,
    required String content,
  }) async {
    final error = insertError;
    if (error != null) throw error;
    lastInsert = {'user_code': userCode, 'content': content};
    final row = <String, dynamic>{
      'id': 'message-1',
      ...lastInsert!,
      'created_at': '2026-08-18T12:00:00.000Z',
    };
    rows.add(row);
    return row;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchMessages() => snapshots.stream;
}

void main() {
  test(
    'insert confirms user_code and content before returning the message',
    () async {
      final gateway = _FakeChatGateway();
      final service = ChatService(gateway: gateway);

      final message = await service.sendMessage('User-A1B2', 'Alerta vecinal');

      expect(gateway.lastInsert, {
        'user_code': 'User-A1B2',
        'content': 'Alerta vecinal',
      });
      expect(message.id, 'message-1');
    },
  );

  test('a new service reloads persisted messages from the gateway', () async {
    final gateway = _FakeChatGateway();
    await ChatService(
      gateway: gateway,
    ).sendMessage('User-A1B2', 'Mensaje persistente');

    final restarted = ChatService(gateway: gateway);
    final messages = await restarted.getMessages();

    expect(messages.single.content, 'Mensaje persistente');
  });

  test('realtime snapshot reaches a second client', () async {
    final gateway = _FakeChatGateway();
    final secondClient = ChatService(gateway: gateway);
    final received = expectLater(
      secondClient.getMessagesStream(),
      emits(
        predicate(
          (messages) =>
              messages is List<ChatMessage> &&
              messages.single.id == 'remote-1',
        ),
      ),
    );

    gateway.snapshots.add([
      {
        'id': 'remote-1',
        'user_code': 'User-B3C4',
        'content': 'Mensaje remoto',
        'created_at': '2026-08-18T12:01:00.000Z',
      },
    ]);

    await received;
    await gateway.snapshots.close();
  });
}
