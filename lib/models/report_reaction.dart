import 'dart:collection';

class ReportReaction {
  const ReportReaction({
    required this.id,
    required this.reportId,
    required this.userCode,
    required this.emoji,
    required this.createdAt,
  });

  final String id;
  final String reportId;
  final String userCode;
  final String emoji;
  final DateTime createdAt;

  factory ReportReaction.fromMap(Map<String, dynamic> map) {
    return ReportReaction(
      id: map['id'] as String,
      reportId: map['report_id'] as String,
      userCode: map['user_code'] as String,
      emoji: normalizeEmoji(map['reaction_type'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static String normalizeEmoji(String value) {
    return switch (value) {
      'shield' => '🛡️',
      'alert' => '⚠️',
      'check' || 'pray' => '🙏',
      'surprised' => '😮',
      _ => value,
    };
  }
}

class ReactionSummary {
  const ReactionSummary({required this.counts, this.currentUserEmoji});

  final Map<String, int> counts;
  final String? currentUserEmoji;

  factory ReactionSummary.fromReactions(
    Iterable<ReportReaction> reactions, {
    required String currentUserCode,
  }) {
    final latestByUser = <String, ReportReaction>{};
    for (final reaction in reactions) {
      final existing = latestByUser[reaction.userCode];
      if (existing == null || reaction.createdAt.isAfter(existing.createdAt)) {
        latestByUser[reaction.userCode] = reaction;
      }
    }

    final totals = <String, int>{};
    for (final reaction in latestByUser.values) {
      totals.update(reaction.emoji, (count) => count + 1, ifAbsent: () => 1);
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) {
        final countComparison = b.value.compareTo(a.value);
        return countComparison != 0 ? countComparison : a.key.compareTo(b.key);
      });

    return ReactionSummary(
      counts: UnmodifiableMapView(Map<String, int>.fromEntries(sorted)),
      currentUserEmoji: latestByUser[currentUserCode]?.emoji,
    );
  }

  static const empty = ReactionSummary(counts: <String, int>{});
}

enum ReactionMutationAction { set, removed }

class ReactionMutationResult {
  const ReactionMutationResult.success({required this.action, this.emoji})
    : message = null;

  const ReactionMutationResult.failure(this.message)
    : action = null,
      emoji = null;

  final ReactionMutationAction? action;
  final String? emoji;
  final String? message;

  bool get isSuccess => action != null;
}
