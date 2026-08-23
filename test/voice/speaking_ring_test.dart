// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/call_controller_provider.dart';
import 'package:hardline/features/voice/speaking_participants.dart';
import 'package:hardline/features/voice/widgets/speaking_ring.dart';
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

  /// Counts how often the child is rebuilt, which is the thing under test as
  /// much as the colour is.
  int builds = 0;

  Widget host(Widget child) => ProviderScope(
    overrides: [speakingParticipantsProvider.overrideWithValue(speaking)],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(body: child),
    ),
  );

  Widget ring({required String userId, String? roomId}) => SpeakingRing(
    userId: userId,
    roomId: roomId,
    size: 18,
    child: Builder(
      builder: (_) {
        builds++;
        return const SizedBox(width: 18, height: 18);
      },
    ),
  );

  /// The ring's colour, read off the rendered decoration.
  Color? drawnRing(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration as BoxDecoration?;
    return decoration?.border?.top.color;
  }

  setUp(() => builds = 0);

  testWidgets('is invisible while nobody is talking', (tester) async {
    await tester.pumpWidget(host(ring(userId: alice, roomId: room)));

    expect(drawnRing(tester), Colors.transparent);
  });

  testWidgets('lights up when its own person starts', (tester) async {
    await tester.pumpWidget(host(ring(userId: alice, roomId: room)));

    speaking.value = SpeakingParticipants.fromIdentities(room, ['$alice:DEV']);
    await tester.pumpAndSettle();

    expect(drawnRing(tester), ringColour);
  });

  testWidgets('goes out again when they stop', (tester) async {
    await tester.pumpWidget(host(ring(userId: alice, roomId: room)));

    speaking.value = SpeakingParticipants.fromIdentities(room, ['$alice:DEV']);
    await tester.pumpAndSettle();
    speaking.value = SpeakingParticipants.fromIdentities(room, const []);
    await tester.pumpAndSettle();

    expect(drawnRing(tester), Colors.transparent);
  });

  // The reason this widget is stateful rather than a `ValueListenableBuilder`.
  // A busy call reports speakers several times a second; every avatar on
  // screen rebuilding each time, to draw the same thing, is the cost this
  // design exists to avoid.
  testWidgets('does not rebuild when somebody else takes over', (tester) async {
    await tester.pumpWidget(host(ring(userId: alice, roomId: room)));
    final atRest = builds;

    for (var i = 0; i < 5; i++) {
      speaking.value = SpeakingParticipants.fromIdentities(room, [
        '$bob:DEV$i',
      ]);
      await tester.pump();
    }

    expect(builds, atRest);
    expect(drawnRing(tester), Colors.transparent);
  });

  testWidgets('does not rebuild when its own person keeps talking', (
    tester,
  ) async {
    await tester.pumpWidget(host(ring(userId: alice, roomId: room)));

    speaking.value = SpeakingParticipants.fromIdentities(room, ['$alice:DEV']);
    await tester.pumpAndSettle();
    final afterLighting = builds;

    // The same report again, as a real call sends it while somebody talks on.
    for (var i = 0; i < 5; i++) {
      speaking.value = SpeakingParticipants.fromIdentities(room, [
        '$alice:DEV',
      ]);
      await tester.pump();
    }

    expect(builds, afterLighting);
    expect(drawnRing(tester), ringColour);
  });

  // Somebody in two calls at once is listed under both channels; only the one
  // we joined can say whether they are talking.
  testWidgets('stays dark for a call in another room', (tester) async {
    await tester.pumpWidget(host(ring(userId: alice, roomId: room)));

    speaking.value = SpeakingParticipants.fromIdentities(
      '!elsewhere:example.org',
      ['$alice:DEV'],
    );
    await tester.pumpAndSettle();

    expect(drawnRing(tester), Colors.transparent);
  });

  // What the user footer does: it belongs to no room, and only asks whether
  // the microphone is picking us up.
  testWidgets('without a room, follows whichever call we are in', (
    tester,
  ) async {
    await tester.pumpWidget(host(ring(userId: alice)));

    speaking.value = SpeakingParticipants.fromIdentities(room, ['$alice:DEV']);
    await tester.pumpAndSettle();

    expect(drawnRing(tester), ringColour);
  });

  // The sidebar recycles rows. A ring that kept the previous occupant's answer
  // would light up for the wrong person.
  testWidgets('follows the row onto a different person', (tester) async {
    await tester.pumpWidget(host(ring(userId: alice, roomId: room)));
    speaking.value = SpeakingParticipants.fromIdentities(room, ['$alice:DEV']);
    await tester.pumpAndSettle();
    expect(drawnRing(tester), ringColour);

    await tester.pumpWidget(host(ring(userId: bob, roomId: room)));
    await tester.pumpAndSettle();

    expect(drawnRing(tester), Colors.transparent);
  });

  testWidgets('a call ending puts every ring out', (tester) async {
    await tester.pumpWidget(host(ring(userId: alice, roomId: room)));
    speaking.value = SpeakingParticipants.fromIdentities(room, ['$alice:DEV']);
    await tester.pumpAndSettle();

    speaking.value = const SpeakingParticipants.silent();
    await tester.pumpAndSettle();

    expect(drawnRing(tester), Colors.transparent);
  });
}
