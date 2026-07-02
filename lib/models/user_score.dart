class UserScore {
  final String id;
  final String userCode;
  final String gameType; // 'trivia' or 'patrol'
  final int score;
  final DateTime createdAt;

  UserScore({
    required this.id,
    required this.userCode,
    required this.gameType,
    required this.score,
    required this.createdAt,
  });

  factory UserScore.fromMap(Map<String, dynamic> map) {
    return UserScore(
      id: map['id'] as String,
      userCode: map['user_code'] as String,
      gameType: map['game_type'] as String,
      score: map['score'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_code': userCode,
      'game_type': gameType,
      'score': score,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
