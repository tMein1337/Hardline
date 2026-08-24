// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/overlay/overlay_layout.dart';
import 'package:hardline/features/overlay/overlay_wire.dart';

void main() {
  const palette = OverlayPalette(
    speakingRing: 0xFFFF7A18,
    text: 0xFFFFFFFF,
    plate: 0xCC000000,
  );

  group('the wire between the two isolates', () {
    test('a snapshot survives the round trip, avatar bytes and all', () {
      final snapshot = OverlaySnapshot(
        people: [
          OverlayPerson(
            userId: '@alice:example.org',
            name: 'Alice',
            avatar: Uint8List.fromList([1, 2, 3, 250, 0, 255]),
          ),
          const OverlayPerson(
            userId: '@bob:example.org',
            name: 'Bob',
            avatar: null,
          ),
        ],
        layout: const OverlayLayout(
          id: 'gaming',
          name: 'Gaming',
          x: 0.42,
          y: 0.66,
          horizontal: true,
          avatarSize: 56,
          showNames: false,
          idleOpacity: 0.3,
        ),
        palette: palette,
        editing: true,
      );

      final decoded = decodeOverlayMessage(snapshot.encode());

      expect(decoded, isA<OverlaySnapshot>());
      expect(decoded, snapshot);
      expect((decoded! as OverlaySnapshot).people.first.avatar, [
        1,
        2,
        3,
        250,
        0,
        255,
      ]);
    });

    test('a speaking update survives the round trip', () {
      const speaking = OverlaySpeaking({
        '@alice:example.org',
        '@bob:example.org',
      });

      expect(decodeOverlayMessage(speaking.encode()), speaking);
    });

    test('an edit survives the round trip', () {
      const edit = OverlayEdit(
        OverlayLayout(id: 'gaming', name: 'Gaming', x: 0.1, y: 0.9),
      );

      final decoded = decodeOverlayMessage(edit.encode());

      expect(decoded, isA<OverlayEdit>());
      expect((decoded! as OverlayEdit).layout.x, 0.1);
      expect((decoded as OverlayEdit).layout.y, 0.9);
    });

    // Not a trust boundary — both ends are this app — but a hot reload can put
    // the two engines a version apart, and a stale HUD beats a dead one.
    test('anything unreadable is dropped rather than thrown', () {
      expect(decodeOverlayMessage(null), isNull);
      expect(decodeOverlayMessage(''), isNull);
      expect(decodeOverlayMessage('not json at all'), isNull);
      expect(decodeOverlayMessage('[1,2,3]'), isNull);
      expect(decodeOverlayMessage('{"kind":"from the future"}'), isNull);
    });

    test('a snapshot missing everything still decodes to something drawable', () {
      final decoded =
          decodeOverlayMessage('{"kind":"snapshot"}')! as OverlaySnapshot;

      expect(decoded.people, isEmpty);
      expect(decoded.editing, isFalse);
      expect(decoded.layout.avatarSize, greaterThan(0));
    });

    test('an avatar that is not base64 falls back to no avatar', () {
      final decoded =
          decodeOverlayMessage(
                '{"kind":"snapshot","people":[{"userId":"@a:b","name":"A",'
                '"avatar":"!!!not base64!!!"}]}',
              )!
              as OverlaySnapshot;

      expect(decoded.people.single.avatar, isNull);
    });

    // The reason there are two message kinds at all: this one is sent several
    // times a second, and it must not be carrying kilobytes of avatar with it.
    test('a speaking update carries nothing but ids', () {
      const speaking = OverlaySpeaking({'@alice:example.org'});

      expect(speaking.encode(), isNot(contains('avatar')));
      expect(speaking.encode().length, lessThan(120));
    });
  });
}
