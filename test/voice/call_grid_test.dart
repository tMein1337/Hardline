// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/call_controller_provider.dart';
import 'package:hardline/features/voice/live_participant.dart';
import 'package:hardline/features/voice/speaking_participants.dart';
import 'package:hardline/features/voice/widgets/call_grid.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';

void main() {
  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);
  final ringColour = AppPalettes.dark.voiceSpeakingRing;

  const room = '!channel:example.org';
  const alice = '@alice:example.org';
  const bob = '@bob:example.org';

  late ValueNotifier<SpeakingParticipants> speaking;

  setUp(() => speaking = ValueNotifier(const SpeakingParticipants.silent()));
  tearDown(() => speaking.dispose());

  LiveParticipant person(
    String user, {
    String name = '',
    bool muted = false,
    bool local = false,
  }) => LiveParticipant(
    userId: user,
    identity: '$user:DEVICE',
    deviceId: 'DEVICE',
    displayName: name.isEmpty ? user : name,
    avatarMxc: null,
    isLocal: local,
    micMuted: muted,
    feeds: const [],
  );

  Widget host(List<LiveParticipant> people) => ProviderScope(
    overrides: [speakingParticipantsProvider.overrideWithValue(speaking)],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 700,
          child: CallTileGrid(tiles: tilesFor(people), roomId: room),
        ),
      ),
    ),
  );

  /// The tile border's colour, read off what was actually rendered.
  ///
  /// The borders are the outermost `AnimatedContainer`s in the tree, in tile
  /// order; the rings inside avatar tiles are the alternating ones after them,
  /// so both are found by walking the ancestors of each name instead.
  Color? borderAround(WidgetTester tester, String label) {
    final container = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          )
          .last,
    );
    return (container.decoration as BoxDecoration?)?.border?.top.color;
  }

  testWidgets('somebody sending no video still gets a tile with their name', (
    tester,
  ) async {
    await tester.pumpWidget(
      host([person(alice, name: 'Alice'), person(bob, name: 'Bob')]),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  // The old stage drew a video surface or nothing at all, so a voice-only call
  // left the chat column exactly as it was.
  testWidgets('a voice-only call is not an empty grid', (tester) async {
    await tester.pumpWidget(host([person(alice, name: 'Alice')]));

    expect(find.byType(SizedBox), findsWidgets);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('our own tile says so, and still gives the account name', (
    tester,
  ) async {
    await tester.pumpWidget(host([person(alice, name: 'Alice', local: true)]));

    expect(find.text('Alice (you)'), findsOneWidget);
  });

  testWidgets('a muted microphone shows on the tile', (tester) async {
    await tester.pumpWidget(
      host([person(alice, name: 'Alice', muted: true), person(bob)]),
    );

    expect(find.byIcon(Icons.mic_off), findsOneWidget);
  });

  testWidgets('nothing is lit while the call is quiet', (tester) async {
    await tester.pumpWidget(host([person(alice, name: 'Alice')]));

    expect(borderAround(tester, 'Alice'), Colors.transparent);
  });

  testWidgets('only the speaker lights up', (tester) async {
    await tester.pumpWidget(
      host([person(alice, name: 'Alice'), person(bob, name: 'Bob')]),
    );

    speaking.value = const SpeakingParticipants(roomId: room, userIds: {alice});
    await tester.pumpAndSettle();

    expect(borderAround(tester, 'Alice'), ringColour);
    expect(borderAround(tester, 'Bob'), Colors.transparent);
  });

  // A ring must not leak between calls: somebody talking in a channel we are
  // not connected to cannot be heard, so drawing them as audible is a lie.
  testWidgets('a call in another room does not light this grid', (
    tester,
  ) async {
    await tester.pumpWidget(host([person(alice, name: 'Alice')]));

    speaking.value = const SpeakingParticipants(
      roomId: '!elsewhere:example.org',
      userIds: {alice},
    );
    await tester.pumpAndSettle();

    expect(borderAround(tester, 'Alice'), Colors.transparent);
  });

  testWidgets('an empty call renders nothing at all', (tester) async {
    await tester.pumpWidget(host(const []));

    expect(find.byType(AnimatedContainer), findsNothing);
  });

  // Every tile is the same size, which is what makes a person sending three
  // streams occupy three people's worth of the grid.
  testWidgets('tiles are all the same size', (tester) async {
    await tester.pumpWidget(
      host([
        person(alice, name: 'Alice'),
        person(bob, name: 'Bob'),
        person('@carol:example.org', name: 'Carol'),
      ]),
    );

    final sizes = ['Alice', 'Bob', 'Carol']
        .map(
          (name) => tester
              .getSize(
                find
                    .ancestor(
                      of: find.text(name),
                      matching: find.byType(AnimatedContainer),
                    )
                    .last,
              )
              .width,
        )
        .toSet();

    expect(sizes, hasLength(1));
  });
}
