// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../core/util/initials.dart';
import '../overlay_layout.dart';
import '../overlay_wire.dart';

/// How long a person takes to fade in and out.
///
/// The same 120ms the sidebar's speaking ring uses, deliberately: the two are
/// the same signal about the same person, and a HUD that reacted on a different
/// beat would read as a second, disagreeing indicator.
const _fade = Duration(milliseconds: 120);

const _ringWidth = 2.0;
const _avatarRadiusFraction = 0.28;

/// The overlay's contents: who is in the call, and who is talking.
///
/// Draws nothing but the people. The window underneath it is transparent, so
/// everything not painted here is the game.
///
/// Runs in the overlay isolate, which has no Riverpod container, no Matrix
/// client and no theme — so this takes a plain snapshot and a set of ids, and
/// every colour arrives in [OverlaySnapshot.palette]. That is a constraint, not
/// a style: the two engines cannot share anything by reference.
class OverlayHud extends StatelessWidget {
  const OverlayHud({
    super.key,
    required this.snapshot,
    required this.speaking,
    this.onDrag,
    this.onDragEnd,
  });

  final OverlaySnapshot snapshot;
  final Set<String> speaking;

  /// Called with a new fractional position while the roster is dragged.
  /// Null outside edit mode, which is also when the window is click-through
  /// and no gesture could arrive anyway.
  final void Function(double x, double y)? onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final layout = snapshot.layout;
    final editing = snapshot.editing;

    // Something to aim at while laying the HUD out over an empty call. Without
    // it, arranging the overlay would mean asking somebody else to talk.
    final people = editing && snapshot.people.isEmpty
        ? _placeholders
        : snapshot.people;

    return LayoutBuilder(
      builder: (context, constraints) {
        final roster = _Roster(
          people: people,
          speaking: editing ? {_placeholders.first.userId} : speaking,
          layout: layout,
          palette: snapshot.palette,
          editing: editing,
        );

        return Stack(
          children: [
            if (editing) _EditBackdrop(palette: snapshot.palette),
            Positioned(
              // Rounded to whole pixels. A rectangle only escapes
              // antialiasing when its edges land on pixel boundaries — at
              // x = 137.4 the compositor blends the leftmost column, and that
              // blend is with the colour key.
              left: (layout.x * constraints.maxWidth).roundToDouble(),
              top: (layout.y * constraints.maxHeight).roundToDouble(),
              child: editing
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        // Fractions of the monitor, not pixels: a layout made
                        // at one resolution has to land in the same place when
                        // a game changes it.
                        final x =
                            (layout.x + details.delta.dx / constraints.maxWidth)
                                .clamp(0.0, 1.0);
                        final y =
                            (layout.y +
                                    details.delta.dy / constraints.maxHeight)
                                .clamp(0.0, 1.0);
                        onDrag?.call(x, y);
                      },
                      onPanEnd: (_) => onDragEnd?.call(),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: roster,
                      ),
                    )
                  : roster,
            ),
          ],
        );
      },
    );
  }
}

/// A wash over the game while the HUD is being arranged.
///
/// Edit mode has already taken the foreground and cost the game its
/// fullscreen; saying so is better than leaving somebody to wonder whether the
/// overlay is stuck.
class _EditBackdrop extends StatelessWidget {
  const _EditBackdrop({required this.palette});

  final OverlayPalette palette;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // Opaque, where it used to be a 35% wash. Colour keying is a hard cut —
      // a translucent layer over the key stops *being* the key and turns the
      // whole monitor into a tinted sheet rather than a wash over the game.
      // Edit mode has the foreground anyway, so a solid backdrop costs nothing
      // and is what makes "you are arranging, not watching" obvious.
      child: ColoredBox(
        color: Color(palette.plate),
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(palette.plate),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(
                  'Drag to place the overlay. Press the edit chord again when '
                  'you are done.',
                  style: TextStyle(
                    color: Color(palette.text),
                    fontSize: 13,
                    fontFamily: 'Segoe UI',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Roster extends StatelessWidget {
  const _Roster({
    required this.people,
    required this.speaking,
    required this.layout,
    required this.palette,
    required this.editing,
  });

  final List<OverlayPerson> people;
  final Set<String> speaking;
  final OverlayLayout layout;
  final OverlayPalette palette;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final person in people)
        _Person(
          key: ValueKey(person.userId),
          person: person,
          speaking: speaking.contains(person.userId),
          layout: layout,
          palette: palette,
          // In edit mode everybody stays visible whatever the idle opacity is
          // set to, or arranging a HUD that is invisible by design would mean
          // arranging nothing.
          forceVisible: editing,
        ),
    ];

    return layout.horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: entries)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries,
          );
  }
}

class _Person extends StatelessWidget {
  const _Person({
    super.key,
    required this.person,
    required this.speaking,
    required this.layout,
    required this.palette,
    required this.forceVisible,
  });

  final OverlayPerson person;
  final bool speaking;
  final OverlayLayout layout;
  final OverlayPalette palette;
  final bool forceVisible;

  @override
  Widget build(BuildContext context) {
    final size = layout.avatarSize;
    final radius = size * _avatarRadiusFraction;

    return Padding(
      padding: const EdgeInsets.all(4),
      // Solid, always. The fade lives on the window now.
      //
      // This was an `AnimatedOpacity` down to `layout.idleOpacity`, and it
      // cannot stay one: the window is colour-keyed (see `kChromaKey`), so a
      // half-transparent avatar blends towards magenta rather than towards the
      // game — a quiet roster would have appeared as pink ghosts on an opaque
      // patch. `OverlayController` applies `idleOpacity` to the whole window
      // instead, after nobody has spoken for `prefs.linger`.
      //
      // What that costs, and it is the only thing it costs: one person talking
      // brings the whole roster to full rather than just them. The speaking
      // ring below is what still says which of them it is.
      // Rounded again, and the fringe is no longer a reason not to be.
      //
      // These were briefly squared into one solid rectangle, because a curved
      // edge antialiases into the colour key and every corner wore a thin
      // magenta line. Squaring was the wrong fix: it could not survive
      // fractional text widths or a display at 125%, where a whole logical
      // pixel is not a whole device pixel, and it made the HUD a slab.
      //
      // The key is derived from the plate now — see `OverlayPalette.chromaKey`
      // — so an edge blends plate-to-almost-plate and cannot be seen. Shape is
      // free again.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: _fade,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius + _ringWidth),
              border: Border.all(
                // The ring appears by gaining a colour, never by gaining a
                // size. Reserving the width is what stops every name on the
                // HUD shifting sideways when somebody draws breath.
                //
                // The quiet colour is the plate, not `Colors.transparent`.
                // Transparent means "show what is behind", and behind is the
                // key — every silent person wore a ring of it.
                color: speaking
                    ? Color(palette.speakingRing)
                    : Color(palette.plate),
                width: _ringWidth,
              ),
            ),
            child: _Avatar(
              person: person,
              size: size,
              radius: radius,
              palette: palette,
            ),
          ),
          if (layout.showNames) ...[
            const SizedBox(width: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                // A plate behind the name, because the background here is
                // whatever the game happens to be drawing and white text on
                // snow is not readable.
                color: Color(palette.plate),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(
                  person.name,
                  style: TextStyle(
                    color: Color(palette.text),
                    fontSize: (size * 0.34).clamp(11.0, 20.0),
                    fontFamily: 'Segoe UI',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.person,
    required this.size,
    required this.radius,
    required this.palette,
  });

  final OverlayPerson person;
  final double size;
  final double radius;
  final OverlayPalette palette;

  @override
  Widget build(BuildContext context) {
    final bytes = person.avatar;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        // An opaque backing, because an avatar is an arbitrary image somebody
        // chose and a PNG with an alpha channel is entirely ordinary. Without
        // it the transparent parts show whatever is behind — the colour key,
        // if the plate did not already cover it — and a cut-out avatar would
        // arrive as a magenta silhouette.
        child: ColoredBox(
          color: Color(palette.plate),
          child: bytes == null
              ? _Initials(person: person, size: size, palette: palette)
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // Bytes the homeserver served and we could not decode.
                  // Initials are what `MxAvatar` falls back to for the same
                  // reason.
                  errorBuilder: (_, _, _) =>
                      _Initials(person: person, size: size, palette: palette),
                ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({
    required this.person,
    required this.size,
    required this.palette,
  });

  final OverlayPerson person;
  final double size;
  final OverlayPalette palette;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Color(palette.plate),
      child: Center(
        child: Text(
          initialsOf(person.name),
          style: TextStyle(
            color: Color(palette.text),
            fontSize: size * 0.4,
            fontFamily: 'Segoe UI',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Stand-ins for laying the HUD out over a call that is empty or quiet.
const _placeholders = [
  OverlayPerson(userId: '#1', name: 'Speaking', avatar: null),
  OverlayPerson(userId: '#2', name: 'Listening', avatar: null),
  OverlayPerson(userId: '#3', name: 'Listening', avatar: null),
];
