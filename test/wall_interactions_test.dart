import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/comment_submission.dart';
import 'package:safezone/models/report_reaction.dart';
import 'package:safezone/services/report_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeWallGateway implements WallInteractionGateway {
  final _reactionController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _commentController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final reactions = <Map<String, dynamic>>[];
  final comments = <Map<String, dynamic>>[];
  final commentTargets = <String>[];
  Object? commentError;
  int _sequence = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchReactions(String reportId) async {
    return reactions.where((row) => row['report_id'] == reportId).toList();
  }

  @override
  Future<Map<String, dynamic>> toggleReaction({
    required String reportId,
    required String userCode,
    required String emoji,
  }) async {
    final current = reactions
        .where(
          (row) => row['report_id'] == reportId && row['user_code'] == userCode,
        )
        .toList();
    final removes =
        current.length == 1 && current.single['reaction_type'] == emoji;
    reactions.removeWhere(
      (row) => row['report_id'] == reportId && row['user_code'] == userCode,
    );
    if (!removes) {
      reactions.add({
        'id': 'reaction-${++_sequence}',
        'report_id': reportId,
        'user_code': userCode,
        'reaction_type': emoji,
        'created_at': DateTime.utc(
          2026,
          8,
          17,
          12,
          0,
          _sequence,
        ).toIso8601String(),
      });
    }
    emitReactions(reportId);
    return {
      'action': removes ? 'removed' : 'set',
      'reaction_type': removes ? null : emoji,
    };
  }

  void emitReactions(String reportId) {
    _reactionController.add(
      reactions.where((row) => row['report_id'] == reportId).toList(),
    );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchReactions(String reportId) async* {
    yield reactions.where((row) => row['report_id'] == reportId).toList();
    yield* _reactionController.stream;
  }

  @override
  Future<Map<String, dynamic>> insertComment({
    required String reportId,
    required String userCode,
    required String content,
  }) async {
    final error = commentError;
    if (error != null) throw error;
    commentTargets.add(reportId);
    final row = <String, dynamic>{
      'id': 'comment-${++_sequence}',
      'report_id': reportId,
      'user_code': userCode,
      'comment_text': content,
      'created_at': DateTime.utc(
        2026,
        8,
        17,
        12,
        0,
        _sequence,
      ).toIso8601String(),
    };
    comments.add(row);
    _commentController.add(
      comments.where((item) => item['report_id'] == reportId).toList(),
    );
    return row;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchComments(String reportId) async* {
    yield comments.where((row) => row['report_id'] == reportId).toList();
    yield* _commentController.stream;
  }

  Future<void> close() async {
    await _reactionController.close();
    await _commentController.close();
  }
}

Map<String, dynamic> _reaction({
  required String id,
  required String user,
  required String emoji,
  required DateTime createdAt,
}) {
  return {
    'id': id,
    'report_id': 'report-1',
    'user_code': user,
    'reaction_type': emoji,
    'created_at': createdAt.toIso8601String(),
  };
}

void main() {
  test('summary keeps one latest reaction per user and sorts by count', () {
    final now = DateTime.utc(2026, 8, 17, 12);
    final rows = <Map<String, dynamic>>[
      _reaction(id: '1', user: 'A', emoji: '❤️', createdAt: now),
      _reaction(
        id: '2',
        user: 'A',
        emoji: '😮',
        createdAt: now.add(const Duration(seconds: 1)),
      ),
      _reaction(id: '3', user: 'B', emoji: '😮', createdAt: now),
      _reaction(id: '4', user: 'C', emoji: '❤️', createdAt: now),
      _reaction(id: '5', user: 'D', emoji: '😮', createdAt: now),
    ];

    final summary = ReactionSummary.fromReactions(
      rows.map(ReportReaction.fromMap),
      currentUserCode: 'A',
    );

    expect(summary.currentUserEmoji, '😮');
    expect(summary.counts, <String, int>{'😮': 3, '❤️': 1});
    expect(summary.counts.keys.first, '😮');
  });

  test('legacy reaction identifiers are displayed as their original emoji', () {
    final row = _reaction(
      id: 'legacy',
      user: 'A',
      emoji: 'shield',
      createdAt: DateTime.utc(2026, 8, 17),
    );
    expect(ReportReaction.fromMap(row).emoji, '🛡️');
  });

  test('user can set, change and remove one reaction', () async {
    final gateway = _FakeWallGateway();
    addTearDown(gateway.close);
    final service = ReportService(wallGateway: gateway);

    final first = await service.toggleEmojiReaction('report-1', 'A', '❤️');
    expect(first.action, ReactionMutationAction.set);
    expect(gateway.reactions.single['reaction_type'], '❤️');

    final changed = await service.toggleEmojiReaction('report-1', 'A', '😮');
    expect(changed.action, ReactionMutationAction.set);
    expect(gateway.reactions, hasLength(1));
    expect(gateway.reactions.single['reaction_type'], '😮');

    final removed = await service.toggleEmojiReaction('report-1', 'A', '😮');
    expect(removed.action, ReactionMutationAction.removed);
    expect(gateway.reactions, isEmpty);
  });

  test(
    'duplicate Realtime snapshots never duplicate reaction counts',
    () async {
      final gateway = _FakeWallGateway();
      addTearDown(gateway.close);
      final service = ReportService(wallGateway: gateway);
      final events = <ReactionSummary>[];
      final subscription = service
          .watchReactionSummary('report-1', currentUserCode: 'viewer')
          .listen(events.add);
      addTearDown(subscription.cancel);

      await service.toggleEmojiReaction('report-1', 'A', '❤️');
      gateway.emitReactions('report-1');
      await Future<void>.delayed(Duration.zero);

      expect(events.last.counts, <String, int>{'❤️': 1});
    },
  );

  test(
    'comments use the same stable report projection for report and SOS',
    () async {
      final gateway = _FakeWallGateway();
      addTearDown(gateway.close);
      final service = ReportService(wallGateway: gateway);

      final reportComment = await service.addComment(
        reportId: 'report-regular',
        userCode: 'VEC-1',
        content: 'Comentario normal',
      );
      final sosComment = await service.addComment(
        reportId: 'report-sos-projection',
        userCode: 'VEC-1',
        content: 'Comentario SOS',
      );

      expect(reportComment.isSuccess, isTrue);
      expect(sosComment.isSuccess, isTrue);
      expect(gateway.commentTargets, <String>[
        'report-regular',
        'report-sos-projection',
      ]);
      expect(
        reportComment.comment!.toMap(),
        containsPair('comment_text', 'Comentario normal'),
      );
      expect(reportComment.comment!.toMap(), isNot(contains('content')));
    },
  );

  test('comment schema and foreign-key errors are explicit', () async {
    final gateway = _FakeWallGateway()
      ..commentError = const PostgrestException(
        message: 'column content does not exist',
        code: '42703',
      );
    addTearDown(gateway.close);
    final service = ReportService(wallGateway: gateway);

    final schema = await service.addComment(
      reportId: 'report-1',
      userCode: 'VEC-1',
      content: 'Texto conservado',
    );
    expect(schema.failure, CommentSubmissionFailure.schema);

    gateway.commentError = const PostgrestException(
      message: 'user_code violates profiles foreign key',
      code: '23503',
    );
    final profile = await service.addComment(
      reportId: 'report-1',
      userCode: 'MISSING',
      content: 'Texto conservado',
    );
    expect(profile.failure, CommentSubmissionFailure.missingProfile);
  });
}
