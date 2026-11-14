// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/matrix/space_tree.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/shell/selection_providers.dart';
import 'package:hardline/features/spaces/space_hierarchy_provider.dart';
import 'package:hardline/features/spaces/space_list_provider.dart';
import 'package:hardline/features/spaces/space_summary.dart';
import 'package:matrix/matrix.dart' show SpaceRoomsChunk$2;

import '../support/fake_matrix.dart';

/// The rail as a list of "id@depth", which is all a test needs to read.
List<String> _rail({
  required List<String> spaces,
  Map<String, List<String>> childrenOf = const {},
  String selected = kHomeSpaceId,
}) => [
  for (final branch in railBranches(
    spaces: spaces,
    childrenOf: childrenOf,
    selectedId: selected,
  ))
    '${branch.id}@${branch.depth}',
];

void main() {
  group('railBranches', () {
    test('spaces inside no other are all there, in their own order', () {
      expect(_rail(spaces: ['b', 'a', 'c']), ['b@0', 'a@0', 'c@0']);
    });

    // The rail is a short list of places. A community with a dozen
    // sub-spaces must not push every other space off the screen for somebody
    // who is not even in it at the time.
    test('a space inside another is folded away until its branch is open', () {
      expect(
        _rail(
          spaces: ['games', 'minecraft', 'work'],
          childrenOf: {
            'games': ['minecraft'],
          },
        ),
        ['games@0', 'work@0'],
      );
    });

    test('selecting the parent shows its sub-spaces beneath it', () {
      expect(
        _rail(
          spaces: ['games', 'minecraft', 'factorio', 'work'],
          childrenOf: {
            'games': ['minecraft', 'factorio'],
          },
          selected: 'games',
        ),
        ['games@0', 'minecraft@1', 'factorio@1', 'work@0'],
      );
    });

    // Otherwise selecting the thing you just unfolded would fold it away
    // from under the pointer.
    test('selecting a sub-space keeps its branch open', () {
      expect(
        _rail(
          spaces: ['games', 'minecraft', 'work'],
          childrenOf: {
            'games': ['minecraft'],
          },
          selected: 'minecraft',
        ),
        ['games@0', 'minecraft@1', 'work@0'],
      );
    });

    test('only the selected branch opens, however deep', () {
      final childrenOf = {
        'a': ['a1', 'a2'],
        'a1': ['a1x'],
        'b': ['b1'],
      };
      const spaces = ['a', 'a1', 'a1x', 'a2', 'b', 'b1'];

      expect(_rail(spaces: spaces, childrenOf: childrenOf, selected: 'a1x'), [
        'a@0',
        'a1@1',
        'a1x@2',
        'a2@1',
        'b@0',
      ]);
      // Selecting a1 shows a1x beneath it and still not b's.
      expect(_rail(spaces: spaces, childrenOf: childrenOf, selected: 'a1'), [
        'a@0',
        'a1@1',
        'a1x@2',
        'a2@1',
        'b@0',
      ]);
      expect(_rail(spaces: spaces, childrenOf: childrenOf, selected: 'a2'), [
        'a@0',
        'a1@1',
        'a2@1',
        'b@0',
      ]);
    });

    test('follows the parent\'s order for what is inside it', () {
      expect(
        _rail(
          spaces: ['x', 'y', 'parent'],
          childrenOf: {
            'parent': ['y', 'x'],
          },
          selected: 'parent',
        ),
        ['parent@0', 'y@1', 'x@1'],
      );
    });

    // `m.space.child` lists rooms too, and spaces this account is not in.
    // Neither is a rail entry.
    test('ignores children that are not joined spaces', () {
      expect(
        _rail(
          spaces: ['games'],
          childrenOf: {
            'games': ['!room', 'unjoined-space'],
          },
          selected: 'games',
        ),
        ['games@0'],
      );
    });

    // One place, one entry, one selection.
    test('a space in two spaces is drawn once, under the first', () {
      const spaces = ['a', 'b', 'shared'];
      final childrenOf = {
        'a': ['shared'],
        'b': ['shared'],
      };

      expect(_rail(spaces: spaces, childrenOf: childrenOf, selected: 'a'), [
        'a@0',
        'shared@1',
        'b@0',
      ]);
      // And is not conjured up under the second.
      expect(_rail(spaces: spaces, childrenOf: childrenOf, selected: 'b'), [
        'a@0',
        'b@0',
      ]);
      // Selected, it opens the branch it is actually drawn in.
      expect(
        _rail(spaces: spaces, childrenOf: childrenOf, selected: 'shared'),
        ['a@0', 'shared@1', 'b@0'],
      );
    });

    group('a loop', () {
      // Nothing forbids A listing B and B listing A, and it takes two people
      // a minute to make. Each would be waiting to be drawn beneath the
      // other, and the rail would show neither.
      test('still shows both spaces', () {
        final childrenOf = {
          'a': ['b'],
          'b': ['a'],
        };
        expect(_rail(spaces: ['a', 'b'], childrenOf: childrenOf), ['a@0']);
        expect(
          _rail(spaces: ['a', 'b'], childrenOf: childrenOf, selected: 'a'),
          ['a@0', 'b@1'],
        );
        expect(
          _rail(spaces: ['a', 'b'], childrenOf: childrenOf, selected: 'b'),
          ['a@0', 'b@1'],
        );
      });

      test('of three, and one that lists itself, terminate', () {
        expect(
          _rail(
            spaces: ['a', 'b', 'c', 'self'],
            childrenOf: {
              'a': ['b'],
              'b': ['c'],
              'c': ['a'],
              'self': ['self'],
            },
            selected: 'c',
          ),
          ['a@0', 'b@1', 'c@2', 'self@0'],
        );
      });

      test('reached from outside hangs off what reaches it', () {
        expect(
          _rail(
            spaces: ['root', 'a', 'b'],
            childrenOf: {
              'root': ['a'],
              'a': ['b'],
              'b': ['a'],
            },
            selected: 'b',
          ),
          ['root@0', 'a@1', 'b@2'],
        );
      });
    });

    // A folded entry stands in for everything beneath it, so it has to know
    // what that is — its badge is theirs.
    test('a folded entry names everything beneath it', () {
      final branches = railBranches(
        spaces: ['a', 'a1', 'a1x', 'a2', 'b'],
        childrenOf: {
          'a': ['a1', 'a2'],
          'a1': ['a1x'],
        },
        selectedId: 'b',
      );
      expect(branches.first.id, 'a');
      expect(branches.first.folded, ['a1', 'a1x', 'a2']);
      expect(branches.last.folded, isEmpty);
    });

    test('an open entry is standing in for nothing', () {
      final branches = railBranches(
        spaces: ['a', 'a1', 'a1x'],
        childrenOf: {
          'a': ['a1'],
          'a1': ['a1x'],
        },
        selectedId: 'a',
      );
      // `a` is open; `a1` is shown but not open, so it carries `a1x`.
      expect(branches.map((b) => '${b.id}:${b.folded.join(",")}'), [
        'a:',
        'a1:a1x',
      ]);
    });

    test('a selection that is not a space opens nothing', () {
      expect(
        _rail(
          spaces: ['a', 'a1'],
          childrenOf: {
            'a': ['a1'],
          },
          selected: '!some-room',
        ),
        ['a@0'],
      );
    });
  });

  group('the rail provider', () {
    late FakeMatrixClient client;
    late ProviderContainer container;

    setUp(() {
      client = FakeMatrixClient();
      container = ProviderContainer(
        overrides: [clientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      client.addRoom('!games:x', name: 'Games', space: true);
      client.addRoom('!mc:x', name: 'Minecraft', space: true);
      client.addRoom('!work:x', name: 'Work', space: true);
      client.child('!games:x', '!mc:x');

      client.addRoom('!lobby:x', name: 'Lobby').highlightCount = 1;
      client.addRoom('!creative:x', name: 'Creative')
        ..notificationCount = 4
        ..highlightCount = 2;
      client.child('!games:x', '!lobby:x');
      client.child('!mc:x', '!creative:x');
    });

    List<SpaceSummary> rail() => container.read(spaceListProvider).items;
    SpaceSummary entry(String id) => rail().firstWhere((s) => s.id == id);

    test('nests a sub-space once its parent is selected', () {
      expect(rail().map((s) => s.name), ['Home', 'Games', 'Work']);

      container.read(selectedSpaceIdProvider.notifier).select('!games:x');
      expect(rail().map((s) => '${s.name}@${s.depth}'), [
        'Home@0',
        'Games@0',
        'Minecraft@1',
        'Work@0',
      ]);
    });

    // A space room holds no conversation, so its own counts are always
    // zero. The rail entry used to show exactly those: Home lit up for
    // everything and a space for nothing.
    test('a space carries the unread counts of the rooms in it', () {
      container.read(selectedSpaceIdProvider.notifier).select('!games:x');
      expect(entry('!games:x').highlightCount, 1);
      expect(entry('!mc:x').highlightCount, 2);
      expect(entry('!mc:x').notificationCount, 4);
    });

    // A mention in a sub-space nobody can see is a mention nobody reads.
    test('a folded entry carries what is beneath it as well', () {
      final games = entry('!games:x');
      expect(games.foldedCount, 1);
      expect(games.highlightCount, 3);
      expect(games.notificationCount, 4);
    });

    test('a room listed by a space and its sub-space is counted once', () {
      client.child('!games:x', '!creative:x');
      expect(entry('!games:x').highlightCount, 3);
    });
  });

  group('reading what a space contains', () {
    late FakeMatrixClient client;
    late ProviderContainer container;

    setUp(() {
      client = FakeMatrixClient();
      container = ProviderContainer(
        overrides: [clientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      client.addRoom('!space:x', name: 'Space', space: true);
    });

    Future<SpaceContents> read() =>
        container.read(spaceHierarchyProvider('!space:x').future);

    List<SpaceRoomsChunk$2> page(int from, int count) => [
      for (var i = from; i < from + count; i++)
        FakeMatrixClient.summary('!r$i:x', name: 'Room $i'),
    ];

    // It used to make one request for a hundred rooms and ignore
    // `next_batch`, so a larger space showed its first hundred and no sign
    // there were more.
    test('follows every page', () async {
      client.hierarchyPages['!space:x'] = [
        [FakeMatrixClient.summary('!space:x', space: true), ...page(0, 99)],
        page(99, 100),
        page(199, 7),
      ];

      final contents = await read();

      expect(contents.children, hasLength(206));
      expect(contents.truncated, isFalse);
      expect(client.calls.where((call) => call.startsWith('hierarchy')), [
        'hierarchy !space:x depth=1',
        'hierarchy !space:x depth=1 from=1',
        'hierarchy !space:x depth=1 from=2',
      ]);
    });

    // Without it the endpoint walks into every space beneath this one and
    // returns the lot as one flat list, so a sub-space's rooms were drawn as
    // the parent's own.
    test('asks for one level only', () async {
      client.hierarchyPages['!space:x'] = [page(0, 1)];
      await read();
      expect(client.calls.single, 'hierarchy !space:x depth=1');
    });

    test('does not list the space inside itself', () async {
      client.hierarchyPages['!space:x'] = [
        [FakeMatrixClient.summary('!space:x', space: true), ...page(0, 2)],
      ];
      expect((await read()).children.map((c) => c.roomId), ['!r0:x', '!r1:x']);
    });

    test('stops at the ceiling and says so', () async {
      client.hierarchyPages['!space:x'] = [
        for (var i = 0; i < 15; i++) page(i * 100, 100),
      ];

      final contents = await read();

      expect(contents.truncated, isTrue);
      expect(contents.children, hasLength(kMaxHierarchyRooms));
      expect(client.calls, hasLength(10));
    });

    // A token with an empty page would otherwise be followed for ever.
    test('gives up on a server that pages without sending anything', () async {
      client.hierarchyPages['!space:x'] = [page(0, 3), [], page(3, 3)];

      final contents = await read();

      expect(contents.children, hasLength(3));
      expect(contents.truncated, isTrue);
      expect(client.calls, hasLength(2));
    });

    test('marks what is a space and what is already joined', () async {
      client.addRoom('!joined:x', name: 'Joined');
      client.hierarchyPages['!space:x'] = [
        [
          FakeMatrixClient.summary('!joined:x', name: 'Joined'),
          FakeMatrixClient.summary('!sub:x', name: 'Sub', space: true),
        ],
      ];

      final children = (await read()).children;

      expect(children[0].joined, isTrue);
      expect(children[0].isSpace, isFalse);
      expect(children[1].joined, isFalse);
      expect(children[1].isSpace, isTrue);
    });
  });
}
