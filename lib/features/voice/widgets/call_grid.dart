// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../call_controller_provider.dart';
import '../call_grid_layout.dart';
import '../live_participant.dart';
import '../voice_participant.dart';
import 'speaking_border.dart';
import 'speaking_ring.dart';
import 'user_audio_menu.dart';

/// Gap between tiles, and the inset around the whole grid.
const _gap = 8.0;

/// Everyone in this channel's call, one tile each, plus one more per stream.
///
/// The rule the layout exists to express: a tile is a *stream*, not a person —
/// except for people sending nothing, who get one tile with their face in it.
/// So somebody sharing a camera and two screens occupies three cells, which is
/// what "allocated the space of that many people" means, and it needs no
/// special case because every cell is the same size.
///
/// Replaces the old `CallStage`, which drew a `Row` of `Expanded` tiles: ten
/// participants produced ten slivers, and anybody with their camera off
/// produced nothing at all.
class CallGrid extends ConsumerWidget {
  const CallGrid({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(callControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isInCallFor(roomId)) return const SizedBox.shrink();

        return CallTileGrid(
          tiles: tilesFor(controller.participants),
          roomId: roomId,
        );
      },
    );
  }
}

/// The grid itself, over a list of tiles somebody else worked out.
///
/// Split from [CallGrid] so the layout and the tile chrome can be driven from
/// hand-built values in a test. The controller needs a `Client`, a token
/// service and a live SFU connection before it can name a single participant,
/// none of which a widget test can supply — and none of which this needs.
class CallTileGrid extends StatelessWidget {
  const CallTileGrid({super.key, required this.tiles, required this.roomId});

  final List<CallTile> tiles;

  /// Only the speaking indicators need it, and only to refuse to light up for
  /// a call other than the one we joined.
  final String roomId;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    return ColoredBox(
      color: context.colors.videoTileBackground,
      child: Padding(
        padding: const EdgeInsets.all(_gap),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shape = chooseGrid(
              tiles.length,
              constraints.biggest,
              spacing: _gap,
            );
            if (shape.isEmpty) return const SizedBox.shrink();

            return _Rows(shape: shape, tiles: tiles, roomId: roomId);
          },
        ),
      ),
    );
  }
}

/// Lays the tiles out row by row, centring a short last row.
///
/// A `Column` of `Row`s rather than a `GridView`: the shape is already decided
/// and every cell has a fixed size, so scrolling, delegates and viewport
/// arithmetic would all be machinery for a problem that is not there.
class _Rows extends StatelessWidget {
  const _Rows({required this.shape, required this.tiles, required this.roomId});

  final GridShape shape;
  final List<CallTile> tiles;
  final String roomId;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (var row = 0; row < shape.rows; row++) {
      final first = row * shape.columns;
      if (first >= tiles.length) break;
      final last = (first + shape.columns).clamp(0, tiles.length);

      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = first; i < last; i++) ...[
              if (i > first) const SizedBox(width: _gap),
              SizedBox(
                width: shape.tile.width,
                height: shape.tile.height,
                child: _Tile(
                  // Keyed by the publication, so a tile that merely moves is
                  // moved rather than rebuilt — which on a video tile is the
                  // difference between keeping the texture and recreating it.
                  key: ValueKey(tiles[i].key),
                  tile: tiles[i],
                  roomId: roomId,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          rows[i],
        ],
      ],
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({super.key, required this.tile, required this.roomId});

  final CallTile tile;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = context.metrics.rowRadius;

    return GestureDetector(
      // The same menu the sidebar row opens, from the tile. Volume is a
      // property of your own playback and the grid is where you are actually
      // listening from, so being sent back to the sidebar to turn somebody
      // down was the wrong way round.
      //
      // Deliberately not `onTap` as well: a tile is a video surface, and
      // pairing a tap with a double-tap or a menu would put a delay on every
      // click into a call.
      onSecondaryTap: () => _openAudioMenu(context, ref),
      child: SpeakingBorder(
        userId: tile.person.userId,
        // Scoped to this channel, for the reason the sidebar rows are:
        // somebody in two calls at once is only lit under the one we can hear.
        roomId: roomId,
        radius: radius,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: tile.isVideo
              ? _VideoBody(tile: tile)
              : _AvatarBody(person: tile.person),
        ),
      ),
    );
  }

  void _openAudioMenu(BuildContext context, WidgetRef ref) {
    // Every device this person is connected from, not just the one this tile
    // draws: volume is stored per device, and somebody on a laptop and a
    // phone needs both sliders whichever of their tiles was clicked.
    final deviceIds = [
      for (final person in ref.read(callControllerProvider).participants)
        if (person.userId == tile.person.userId) person.deviceId,
    ]..sort();

    unawaited(
      UserAudioMenu.show(
        context,
        VoiceParticipant.fromLive(tile.person, deviceIds: deviceIds),
      ),
    );
  }
}

class _VideoBody extends StatelessWidget {
  const _VideoBody({required this.tile});

  final CallTile tile;

  @override
  Widget build(BuildContext context) {
    final feed = tile.feed!;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: context.colors.videoTilePlaceholder),
        lk.VideoTrackRenderer(
          feed.track,
          // `contain`: a shared screen cropped to fill would cut off exactly
          // the edges people are usually pointing at.
          fit: lk.VideoViewFit.contain,
          // Our own camera is mirrored so it behaves like a mirror; a shared
          // screen must never be, or text in it reads backwards.
          mirrorMode: feed.isLocal && !feed.isScreenShare
              ? lk.VideoViewMirrorMode.mirror
              : lk.VideoViewMirrorMode.off,
        ),
        // Bottom *right*, deliberately: with several streams on screen the
        // question a caption answers is "whose is this one", and it is asked
        // while the eye is already travelling towards the next tile.
        Positioned(
          right: 6,
          bottom: 6,
          child: _NameChip(person: tile.person, feed: feed),
        ),
      ],
    );
  }
}

/// The tile for somebody sending no video at all.
///
/// The case the old stage could not express, and the reason a voice-only call
/// used to leave the chat column exactly as it was.
class _AvatarBody extends StatelessWidget {
  const _AvatarBody({required this.person});

  final LiveParticipant person;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ColoredBox(
      color: colors.videoTilePlaceholder,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Proportional to the cell, so a two-person call shows faces and a
          // twelve-person call still shows twelve of them. Clamped at both ends
          // because an avatar is a bitmap: past the top it is upscaled mush,
          // and below the bottom the initials stop being readable.
          final avatar = (constraints.biggest.shortestSide * 0.4).clamp(
            24.0,
            96.0,
          );

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpeakingRing(
                userId: person.userId,
                size: avatar,
                child: MxAvatar(
                  name: person.displayName,
                  seed: person.userId,
                  mxcUri: person.avatarMxc,
                  size: avatar,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Deafened first, and it replaces the muted glyph rather
                    // than sitting beside it: somebody deafened is always also
                    // muted (see `setDeafened`), so drawing both would be two
                    // icons for one fact, and the stronger one is the one that
                    // says they cannot hear you either.
                    if (person.deafened) ...[
                      Icon(
                        Icons.headset_off,
                        size: 13,
                        color: colors.voiceDeafenedIcon,
                      ),
                      const SizedBox(width: 4),
                    ] else if (person.micMuted) ...[
                      Icon(
                        Icons.mic_off,
                        size: 13,
                        color: colors.voiceMutedIcon,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        labelFor(person),
                        style: context.text.subtitle.copyWith(
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({required this.person, required this.feed});

  final LiveParticipant person;
  final CallVideoFeed feed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.scrim,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (feed.isScreenShare) ...[
              Icon(
                Icons.screen_share,
                size: 12,
                color: colors.voiceControlIconActive,
              ),
              const SizedBox(width: 4),
            ],
            if (person.deafened) ...[
              Icon(
                Icons.headset_off,
                size: 12,
                color: colors.voiceDeafenedIcon,
              ),
              const SizedBox(width: 4),
            ] else if (person.micMuted) ...[
              Icon(Icons.mic_off, size: 12, color: colors.voiceMutedIcon),
              const SizedBox(width: 4),
            ],
            Text(
              labelFor(person),
              style: context.text.timestamp.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The name a tile is captioned with.
///
/// The account name rather than "You" even for our own tiles: with several
/// streams up, the caption exists to say *whose* stream this is, and one tile
/// labelled by a different rule than the rest breaks the scan. The suffix is
/// what distinguishes them, and it still reads correctly when two of our own
/// shares are on screen at once.
@visibleForTesting
String labelFor(LiveParticipant person) =>
    person.isLocal ? '${person.displayName} (you)' : person.displayName;
