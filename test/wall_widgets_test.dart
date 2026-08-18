import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safezone/models/report_reaction.dart';
import 'package:safezone/screens/wall/wall_screen.dart';
import 'package:safezone/widgets/emoji_reaction_picker.dart';
import 'package:safezone/widgets/reaction_summary_bar.dart';

void main() {
  testWidgets('empty filter has a coherent wall state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WallEmptyState())),
    );
    expect(find.text('No hay alertas en este periodo.'), findsOneWidget);
    expect(
      find.text('Las publicaciones aparecerán aquí en tiempo real.'),
      findsOneWidget,
    );
  });

  testWidgets('zero-count emojis are hidden and an empty hint is shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReactionSummaryBar(
            summary: const ReactionSummary(
              counts: <String, int>{'❤️': 2, '😮': 0},
            ),
            onReactionTap: (_) {},
            onOpenPicker: () {},
          ),
        ),
      ),
    );

    expect(find.text('❤️ 2'), findsOneWidget);
    expect(find.text('😮 0'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReactionSummaryBar(
            summary: ReactionSummary.empty,
            onReactionTap: (_) {},
            onOpenPicker: () {},
          ),
        ),
      ),
    );
    expect(find.text('Mantén presionado para reaccionar'), findsOneWidget);
  });

  testWidgets(
    'emoji selector supports common and custom emoji on Web/Android',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selected = await EmojiReactionPicker.show(context);
                },
                child: const Text('Abrir selector'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir selector'));
      await tester.pumpAndSettle();
      expect(EmojiReactionPicker.commonEmojis.length, greaterThan(4));
      expect(find.byKey(const ValueKey('emoji_picker_❤️')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('emoji_picker_❤️')));
      await tester.pumpAndSettle();
      expect(selected, '❤️');

      await tester.tap(find.text('Abrir selector'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom_emoji_field')),
        '🫶',
      );
      await tester.tap(find.byKey(const ValueKey('submit_custom_emoji')));
      await tester.pumpAndSettle();
      expect(selected, '🫶');
    },
  );

  test('wall interaction sources remain Web compatible', () {
    for (final path in <String>[
      'lib/screens/wall/wall_screen.dart',
      'lib/widgets/emoji_reaction_picker.dart',
      'lib/widgets/reaction_summary_bar.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains("import 'dart:io'")), reason: path);
    }
    final wallSource = File(
      'lib/screens/wall/wall_screen.dart',
    ).readAsStringSync();
    expect(wallSource, contains('onLongPress'));
  });

  test('migration preserves comments and enforces one reaction row', () {
    final sql = File(
      'supabase/migrations/wall_interactions_and_history.sql',
    ).readAsStringSync();
    expect(sql, contains('UNIQUE (report_id, user_code)'));
    expect(sql, contains('archived_report_comments'));
    expect(sql, contains('INSERT INTO archived_reactions'));
    expect(sql, contains('toggle_report_reaction'));
    expect(sql, contains('ADD TABLE reactions'));
    expect(sql, contains('ADD TABLE report_comments'));
  });
}
