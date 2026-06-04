class ChatMessage {
  final String id;
  final String userCode;
  final String content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.userCode,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      userCode: map['user_code'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_code': userCode,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
