// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/overlay/overlay_layout.dart';
import 'package:hardline/features/overlay/overlay_wire.dart';
import 'package:hardline/features/overlay/widgets/overlay_hud.dart';

void main() {
  const ring = 0xFFFF7A18;
  // Opaque, like every colour the HUD is given: the overlay window is
  // colour-keyed, so anything carrying alpha blends towards the key.
  const plate = 0xFF08080A;
  const palette = OverlayPalette(
    speakingRing: ring,
    text: 0xFFFFFFFF,
    plate: plate,
  );

  const alice = '@alice:example.org';
  const bob = '@bob:example.org';

  const people = [
    OverlayPerson(userId: alice, name: 'Alice', avatar: null),
    OverlayPerson(userId: bob, name: 'Bob', avatar: null),
  ];

  /// The HUD is the whole app in the overlay isolate: no Riverpod, no theme,
  /// no Matrix client. Everything it draws is in the snapshot, which is what
  /// makes it testable with nothing but a `MaterialApp` around it.
  Widget host(OverlaySnapshot snapshot, Set<String> speaking) => MaterialApp(
    home: Material(
      type: MaterialType.transparency,
      child: SizedBox(
        // The default test surface, exactly: a larger box overflows it and the
        // positions this file asserts stop meaning anything.
        width: 800,
        height: 600,
        child: OverlayHud(snapshot: snapshot, speaking: speaking),
      ),
    ),
  );

  OverlaySnapshot snapshot({
    List<OverlayPerson> roster = people,
    OverlayLayout layout = const OverlayLayout(id: 'a', name: 'A'),
    bool editing = false,
  }) => OverlaySnapshot(
    people: roster,
    layout: layout,
    palette: palette,
    editing: editing,
  );

  /// Each person's row is keyed by their user id, which is the only handle a
  /// test has on one of several identical-looking entries.
  Finder rowOf(String userId) => find.byKey(ValueKey(userId));

  /// Whether the person is drawn at all.
  ///
  /// There is no per-person opacity to read any more. The window is
  /// colour-keyed, so everything the HUD paints is solid and the dimming
  /// happens on the window instead — see `kChromaKey` and
  /// `OverlayController._onSpeechChanged`. What is left to assert here is who
  /// is on screen and which of them is ringed.
  bool isDrawn(WidgetTester tester, String userId) =>
      rowOf(userId).evaluate().isNotEmpty;

  Color? ringOf(WidgetTester tester, String userId) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: rowOf(userId),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return (container.decoration as BoxDecoration?)?.border?.top.color;
  }

  // The roster is always drawn. Whether any of it is *seen* is the window's
  // opacity, which the controller owns — see overlay_linger_test.dart.
  testWidgets('everybody in the call is drawn, talking or not', (tester) async {
    await tester.pumpWidget(host(snapshot(), const {}));
    await tester.pumpAndSettle();

    expect(isDrawn(tester, alice), isTrue);
    expect(isDrawn(tester, bob), isTrue);
  });

  testWidgets('the roster does not change when somebody starts talking', (
    tester,
  ) async {
    await tester.pumpWidget(host(snapshot(), const {alice}));
    await tester.pumpAndSettle();

    expect(isDrawn(tester, alice), isTrue);
    expect(isDrawn(tester, bob), isTrue);
  });

  testWidgets('the speaker gets the same ring the sidebar draws', (
    tester,
  ) async {
    await tester.pumpWidget(host(snapshot(), const {alice}));
    await tester.pumpAndSettle();

    expect(ringOf(tester, alice), const Color(ring));
    // The plate, not `Colors.transparent`. Transparent means "show what is
    // behind", and behind is the colour key — a quiet person would wear a
    // bright magenta ring.
    expect(ringOf(tester, bob), const Color(plate));
  });

  // `idleOpacity` no longer reaches the widgets at all — it is applied to the
  // window once the linger expires. The HUD must draw the same either way, or
  // the two would fight over the same fact.
  testWidgets('a raised idle opacity changes nothing about the drawing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        snapshot(
          layout: const OverlayLayout(id: 'a', name: 'A', idleOpacity: 0.4),
        ),
        const {alice},
      ),
    );
    await tester.pumpAndSettle();

    expect(isDrawn(tester, alice), isTrue);
    expect(isDrawn(tester, bob), isTrue);
    expect(ringOf(tester, alice), const Color(ring));
    // The plate, not `Colors.transparent`. Transparent means "show what is
    // behind", and behind is the colour key — a quiet person would wear a
    // bright magenta ring.
    expect(ringOf(tester, bob), const Color(plate));
  });

  testWidgets('names can be turned off without losing the avatars', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        snapshot(
          layout: const OverlayLayout(id: 'a', name: 'A', showNames: false),
        ),
        const {alice},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsNothing);
    // Initials stand in for the avatar the app could not fetch, exactly as
    // `MxAvatar` does.
    expect(find.text('AL'), findsOneWidget);
  });

  testWidgets('an empty call draws nothing at all', (tester) async {
    await tester.pumpWidget(host(snapshot(roster: const []), const {}));
    await tester.pumpAndSettle();

    expect(rowOf(alice), findsNothing);
    expect(rowOf(bob), findsNothing);
  });

  // Laying a HUD out over an empty call would otherwise mean asking somebody
  // to join one and talk.
  testWidgets('edit mode shows stand-ins when the call is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(snapshot(roster: const [], editing: true), const {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Speaking'), findsOneWidget);
    expect(find.text('Listening'), findsNWidgets(2));
  });

  testWidgets('edit mode keeps the quiet people visible to be arranged', (
    tester,
  ) async {
    await tester.pumpWidget(host(snapshot(editing: true), const {}));
    await tester.pumpAndSettle();

    expect(isDrawn(tester, alice), isTrue);
    expect(isDrawn(tester, bob), isTrue);
  });

  testWidgets('the layout decides where the roster sits', (tester) async {
    await tester.pumpWidget(
      host(
        snapshot(
          layout: const OverlayLayout(
            id: 'a',
            name: 'A',
            x: 0.5,
            y: 0.25,
            idleOpacity: 1,
          ),
        ),
        const {},
      ),
    );
    await tester.pumpAndSettle();

    final position = tester.getTopLeft(rowOf(alice));

    // Fractions of the monitor, so the same layout lands in the same place when
    // a game changes the resolution.
    expect(position.dx, closeTo(800 * 0.5, 1));
    expect(position.dy, closeTo(600 * 0.25, 1));
  });

  testWidgets('a horizontal layout lays people out across', (tester) async {
    await tester.pumpWidget(
      host(
        snapshot(
          layout: const OverlayLayout(
            id: 'a',
            name: 'A',
            horizontal: true,
            idleOpacity: 1,
          ),
        ),
        const {},
      ),
    );
    await tester.pumpAndSettle();

    final alicePosition = tester.getTopLeft(rowOf(alice));
    final bobPosition = tester.getTopLeft(rowOf(bob));

    expect(bobPosition.dx, greaterThan(alicePosition.dx));
    expect(bobPosition.dy, closeTo(alicePosition.dy, 1));
  });
}
