// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/emoji_data.dart';
import 'package:hardline/features/chat/reactions.dart';
import 'package:hardline/features/chat/widgets/reaction_picker.dart';
import 'package:hardline/features/chat/widgets/reaction_row.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';

const _me = '@me:example.org';

ReactionEvent _r(
  String key,
  String sender,
  int minute, {
  String? id,
  bool sent = true,
}) => (
  key: key,
  senderId: sender,
  eventId: id ?? '\$$key$sender$minute',
  timestamp: DateTime(2026, 1, 1, 12, minute),
  sent: sent,
);

void main() {
  group('summarizeReactions', () {
    test('groups by key in the order each key first appeared', () {
      final summary = summarizeReactions([
        _r('🎉', '@b:x', 3),
        _r('👍', '@a:x', 1),
        _r('👍', '@b:x', 2),
      ], me: _me);

      expect(summary.map((s) => s.key), ['👍', '🎉']);
      expect(summary.first.count, 2);
      expect(summary.first.senderIds, ['@a:x', '@b:x']);
    });

    test('one person counts once per key', () {
      final summary = summarizeReactions([
        _r('👍', '@a:x', 1),
        _r('👍', '@a:x', 2),
      ], me: _me);

      expect(summary.single.count, 1);
    });

    test('knows which reaction is ours, and whether it has been sent', () {
      final summary = summarizeReactions([
        _r('👍', '@a:x', 1),
        _r('👍', _me, 2, id: r'$mine', sent: false),
        _r('❤️', '@a:x', 3),
      ], me: _me);

      expect(summary[0].mine, isTrue);
      expect(summary[0].myEventId, r'$mine');
      expect(summary[0].mySent, isFalse);
      expect(summary[1].mine, isFalse);
    });
  });

  group('describeReaction', () {
    test('names everybody up to five', () {
      expect(describeReaction(['You'], '👍'), 'You reacted with 👍');
      expect(
        describeReaction(['Alice', 'Bob', 'You'], '👍'),
        'Alice, Bob and You reacted with 👍',
      );
    });

    test('counts the rest', () {
      expect(
        describeReaction(['a', 'b', 'c', 'd', 'e', 'f', 'g'], '🎉'),
        'a, b, c, d, e and 2 others reacted with 🎉',
      );
    });
  });

  group('searchEmoji', () {
    test('finds by keyword', () {
      expect(searchEmoji('thumbs'), containsAll(['👍', '👎']));
      expect(searchEmoji('heart').first, isNotEmpty);
    });

    test('every word has to match', () {
      expect(searchEmoji('thumbs up'), ['👍']);
    });

    test('an empty query finds nothing rather than everything', () {
      expect(searchEmoji('  '), isEmpty);
    });
  });

  group('ReactionPicker', () {
    final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);

    Future<String?> open(
      WidgetTester tester,
      Future<void> Function() interact,
    ) async {
      String? picked = 'not closed';
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showReactionPicker(
                    context,
                    anchor: const Rect.fromLTWH(400, 100, 30, 30),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reaction_picker')), findsOneWidget);
      await interact();
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('a quick reaction is one click', (tester) async {
      final picked = await open(
        tester,
        () => tester.tap(find.text('👍').first),
      );
      expect(picked, '👍');
    });

    testWidgets('Enter in the search takes the first match', (tester) async {
      final picked = await open(tester, () async {
        await tester.enterText(
          find.byKey(const Key('reaction_picker_search')),
          'rocket',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
      });
      expect(picked, '🚀');
    });

    testWidgets('text that is no emoji can still be sent', (tester) async {
      final picked = await open(tester, () async {
        await tester.enterText(
          find.byKey(const Key('reaction_picker_search')),
          'lgtm',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('reaction_picker_custom')));
      });
      expect(picked, 'lgtm');
    });
  });
}
