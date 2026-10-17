// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
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

    test(
      'a snapshot missing everything still decodes to something drawable',
      () {
        final decoded =
            decodeOverlayMessage('{"kind":"snapshot"}')! as OverlaySnapshot;

        expect(decoded.people, isEmpty);
        expect(decoded.editing, isFalse);
        expect(decoded.layout.avatarSize, greaterThan(0));
      },
    );

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

  // The rule the whole HUD depends on, and the one that has already been
  // broken once: the overlay window is colour-keyed, so a colour carrying
  // alpha blends towards the key rather than towards the game behind it. The
  // plate arrived as `0xCC000000` — 80% black — and the HUD came up purple.
  //
  // Checked on the defaults rather than on a live palette, because those are
  // what a malformed or missing message resolves to and they are the copy
  // most likely to be forgotten.
  group('every overlay colour is opaque', () {
    int alphaOf(int argb) => (argb >> 24) & 0xFF;

    test('in the defaults a missing palette falls back to', () {
      final palette = decodeOverlayMessage(jsonEncode({'kind': 'snapshot'}));
      expect(palette, isA<OverlaySnapshot>());

      final colors = (palette! as OverlaySnapshot).palette;
      expect(alphaOf(colors.plate), 0xFF, reason: 'plate');
      expect(alphaOf(colors.text), 0xFF, reason: 'text');
      expect(alphaOf(colors.speakingRing), 0xFF, reason: 'speakingRing');
    });

    test('and in a palette that only half decoded', () {
      final decoded = decodeOverlayMessage(
        jsonEncode({
          'kind': 'snapshot',
          'palette': {'text': 0xFFFFFFFF},
        }),
      );

      final colors = (decoded! as OverlaySnapshot).palette;
      expect(alphaOf(colors.plate), 0xFF, reason: 'plate');
      expect(alphaOf(colors.speakingRing), 0xFF, reason: 'speakingRing');
    });
  });

  // The key is derived rather than fixed, and the derivation is what makes an
  // antialiased edge invisible. Two properties matter and neither is obvious
  // from looking at it.
  group('the chroma key', () {
    test('is never the plate itself', () {
      for (final plate in [0xFF08080A, 0xFF000000, 0xFFFFFFFF, 0xFF123456]) {
        final palette = OverlayPalette(
          speakingRing: 0xFFFF7A18,
          text: 0xFFFFFFFF,
          plate: plate,
        );
        expect(palette.chromaKey, isNot(plate), reason: '$plate');
      }
    });

    // If it were far from the plate the fringe would be visible, which is the
    // whole failure this replaced — a magenta key made every rounded corner a
    // pink outline.
    test('is within one step of the plate on every channel', () {
      for (final plate in [0xFF08080A, 0xFF000000, 0xFFFFFFFF]) {
        final key = OverlayPalette(
          speakingRing: 0,
          text: 0,
          plate: plate,
        ).chromaKey;

        for (final shift in [16, 8, 0]) {
          final a = (plate >> shift) & 0xFF;
          final b = (key >> shift) & 0xFF;
          expect((a - b).abs(), lessThanOrEqualTo(1), reason: '$plate');
        }
      }
    });

    test('stays opaque, like everything else the HUD paints', () {
      for (final plate in [0xFF08080A, 0xFF000000, 0xFFFFFFFF]) {
        final key = OverlayPalette(
          speakingRing: 0,
          text: 0,
          plate: plate,
        ).chromaKey;
        expect((key >> 24) & 0xFF, 0xFF, reason: '$plate');
      }
    });
  });
}
