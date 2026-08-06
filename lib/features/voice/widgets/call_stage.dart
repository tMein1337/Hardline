import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../theme/theme_context.dart';
import '../call_controller_provider.dart';
import '../livekit_call_controller.dart';

/// The video area above the message list.
///
/// Renders nothing at all unless we are in *this* room's call and somebody is
/// actually sending video — a voice-only call leaves the chat exactly as it was.
///
/// Bounded in height rather than expanded so the conversation never disappears
/// behind a shared screen; Discord makes the same trade.
class CallStage extends ConsumerWidget {
  const CallStage({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(callControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isInCallFor(roomId)) return const SizedBox.shrink();

        final tiles = controller.videoTiles;
        if (tiles.isEmpty) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight * 0.45
                  : 320,
            ),
            child: Container(
              color: context.colors.videoTileBackground,
              padding: const EdgeInsets.all(8),
              child: _TileLayout(tiles: tiles),
            ),
          ),
        );
      },
    );
  }
}

class _TileLayout extends StatelessWidget {
  const _TileLayout({required this.tiles});

  final List<CallVideoTile> tiles;

  @override
  Widget build(BuildContext context) {
    // A shared screen is the thing people are looking at, so it gets the room
    // and the faces line up beneath it. With no screen share, everyone is equal
    // and a plain row reads better than a hierarchy that is not there.
    final screenShares = tiles.where((t) => t.isScreenShare).toList();
    final cameras = tiles.where((t) => !t.isScreenShare).toList();

    if (screenShares.isEmpty) {
      return Row(
        children: [
          for (final tile in cameras)
            Expanded(child: _VideoTile(key: ValueKey(tile.key), tile: tile)),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            children: [
              for (final tile in screenShares)
                Expanded(
                  child: _VideoTile(key: ValueKey(tile.key), tile: tile),
                ),
            ],
          ),
        ),
        if (cameras.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: Row(
              children: [
                for (final tile in cameras)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _VideoTile(key: ValueKey(tile.key), tile: tile),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({super.key, required this.tile});

  final CallVideoTile tile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.videoTilePlaceholder),
            lk.VideoTrackRenderer(
              tile.track,
              // `contain`: a shared screen cropped to fill would cut off
              // exactly the edges people are usually pointing at.
              fit: lk.VideoViewFit.contain,
              // Our own camera is mirrored so it behaves like a mirror; a
              // shared screen must never be, or text in it reads backwards.
              mirrorMode: tile.isLocal && !tile.isScreenShare
                  ? lk.VideoViewMirrorMode.mirror
                  : lk.VideoViewMirrorMode.off,
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.scrim,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tile.isScreenShare) ...[
                        Icon(
                          Icons.screen_share,
                          size: 12,
                          color: colors.voiceControlIconActive,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        tile.isLocal ? 'You' : tile.displayName,
                        style: context.text.timestamp.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
