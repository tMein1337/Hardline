// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/live_participant.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// A stand-in for a published video track.
///
/// `CallVideoFeed` holds a live `lk.VideoTrack`, which cannot be built without
/// a peer connection — and does not need to be here, because the track is
/// deliberately excluded from equality. That exclusion is most of what these
/// tests are about, so a value that would throw if anything touched it is
/// exactly the right stand-in: nothing should.
class _UntouchedTrack implements lk.VideoTrack {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CallVideoFeed feed(String key, {bool screen = false, bool local = false}) =>
    CallVideoFeed(
      key: key,
      track: _UntouchedTrack(),
      isScreenShare: screen,
      isLocal: local,
    );

LiveParticipant person(
  String user, {
  List<CallVideoFeed> feeds = const [],
  bool muted = false,
  bool local = false,
}) => LiveParticipant(
  userId: user,
  identity: '$user:DEVICE',
  deviceId: 'DEVICE',
  displayName: user,
  avatarMxc: null,
  isLocal: local,
  micMuted: muted,
  feeds: feeds,
);

void main() {
  group('LiveParticipant equality', () {
    test('two reads of an unchanged call compare equal', () {
      final first = person('@alice:example.org', feeds: [feed('a|1')]);
      final second = person('@alice:example.org', feeds: [feed('a|1')]);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    // The point of the whole value type. `participants` is recomputed on every
    // LiveKit event, and most of those change nothing; a list that never
    // compares equal to itself would repaint the grid at event rate.
    test('a list of them compares equal across a recompute', () {
      final before = [
        person('@alice:example.org', feeds: [feed('a|1')]),
        person('@bob:example.org'),
      ];
      final after = [
        person('@alice:example.org', feeds: [feed('a|1')]),
        person('@bob:example.org'),
      ];

      expect(before, after);
    });

    test('a new publication breaks equality', () {
      final before = person('@alice:example.org', feeds: [feed('a|1')]);
      final after = person(
        '@alice:example.org',
        feeds: [feed('a|1'), feed('a|2', screen: true)],
      );

      expect(before, isNot(after));
    });

    test('muting themselves breaks equality', () {
      expect(
        person('@alice:example.org'),
        isNot(person('@alice:example.org', muted: true)),
      );
    });
  });

  group('tilesFor', () {
    const alice = '@alice:example.org';
    const bob = '@bob:example.org';

    test('somebody sending nothing still gets a tile', () {
      final tiles = tilesFor([person(alice)]);

      expect(tiles, hasLength(1));
      expect(tiles.single.isVideo, isFalse);
      expect(tiles.single.person.userId, alice);
    });

    // The requirement in one test: three streams, three cells, and because
    // every cell is the same size that is three people's worth of space.
    test('a camera and two screens are three tiles', () {
      final tiles = tilesFor([
        person(
          alice,
          feeds: [
            feed('a|cam'),
            feed('a|screen1', screen: true),
            feed('a|screen2', screen: true),
          ],
        ),
      ]);

      expect(tiles, hasLength(3));
      expect(tiles.every((tile) => tile.person.userId == alice), isTrue);
      expect(tiles.every((tile) => tile.isVideo), isTrue);
    });

    test('shared screens come before cameras, and faces come last', () {
      final tiles = tilesFor([
        person(alice, feeds: [feed('a|cam')]),
        person(bob, feeds: [feed('b|screen', screen: true)]),
        person('@carol:example.org'),
      ]);

      expect(tiles.map((tile) => tile.key), [
        'b|screen',
        'a|cam',
        'avatar|@carol:example.org:DEVICE',
      ]);
    });

    test('an empty call is an empty grid', () {
      expect(tilesFor(const []), isEmpty);
    });

    // Two devices of the same person are two participants, and each brings its
    // own tiles. Collapsing them would hide one of the two screens.
    test('one person on two devices gets a tile per device', () {
      final laptop = LiveParticipant(
        userId: alice,
        identity: '$alice:LAPTOP',
        deviceId: 'LAPTOP',
        displayName: 'Alice',
        avatarMxc: null,
        isLocal: false,
        micMuted: false,
        feeds: [feed('l|1')],
      );
      final phone = LiveParticipant(
        userId: alice,
        identity: '$alice:PHONE',
        deviceId: 'PHONE',
        displayName: 'Alice',
        avatarMxc: null,
        isLocal: false,
        micMuted: false,
        feeds: [feed('p|1')],
      );

      expect(tilesFor([laptop, phone]), hasLength(2));
    });

    test('a tile key is stable so the texture survives a rebuild', () {
      final once = tilesFor([
        person(alice, feeds: [feed('a|cam')]),
      ]).single;
      final twice = tilesFor([
        person(alice, feeds: [feed('a|cam')]),
      ]).single;

      expect(once.key, twice.key);
      expect(once, twice);
    });
  });

  test('isScreenSharing is true only while a screen feed is up', () {
    expect(person('@alice:example.org').isScreenSharing, isFalse);
    expect(
      person('@alice:example.org', feeds: [feed('a|cam')]).isScreenSharing,
      isFalse,
    );
    expect(
      person(
        '@alice:example.org',
        feeds: [feed('a|s', screen: true)],
      ).isScreenSharing,
      isTrue,
    );
  });
}
