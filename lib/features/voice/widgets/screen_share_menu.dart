// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../call_controller_provider.dart';
import '../livekit_call_controller.dart';

/// What the screen-share button opens once something is already being shared.
///
/// With one share a toggle was enough. With several, the button has to answer
/// *which one* — stopping "the" share is not a question with an answer any
/// more, and a control that picks for you would eventually pick wrong in front
/// of an audience.
///
/// A dialog rather than a popup menu, to match `UserAudioMenu`: the app has one
/// idiom for "a small panel about one thing" and this is it.
class ScreenShareMenu extends ConsumerWidget {
  const ScreenShareMenu({super.key, required this.onAddShare});

  /// Opens the picker and starts another share. Passed in rather than done
  /// here because the picker is `lk.ScreenSelectDialog`, which is contained to
  /// exactly one call site on purpose — see `voice_status_footer.dart`.
  final Future<void> Function() onAddShare;

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function() onAddShare,
  }) => showDialog(
    context: context,
    builder: (context) => ScreenShareMenu(onAddShare: onAddShare),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final controller = ref.watch(callControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final shares = controller.shares;

        // The last share was stopped from in here, or from Windows' own
        // sharing banner. There is nothing left for this dialog to be about.
        if (shares.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
        }

        return AlertDialog(
          backgroundColor: colors.floatingSurface,
          title: Text('Sharing', style: context.text.title),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final share in shares)
                  _ShareRow(
                    share: share,
                    onStop: () => controller.stopScreenShare(share.videoSid),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      // Closed first: the picker is a dialog of its own, and
                      // stacking one on this one leaves the far one unreachable
                      // behind the near one's scrim.
                      Navigator.of(context).pop();
                      await onAddShare();
                    },
                    icon: Icon(Icons.add, size: 16, color: colors.accent),
                    label: Text(
                      'Share another…',
                      style: TextStyle(color: colors.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (shares.length > 1)
              TextButton(
                onPressed: () => controller.stopAllScreenShares(),
                child: Text(
                  'Stop all',
                  style: TextStyle(color: colors.voiceControlDanger),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Done', style: TextStyle(color: colors.accent)),
            ),
          ],
        );
      },
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.share, required this.onStop});

  final LocalShare share;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            Icons.screen_share,
            size: 16,
            color: colors.voiceControlIconActive,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              share.label,
              style: context.text.subtitle.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (share.audioSid != null) ...[
            // The tell that loopback capture actually produced a track. Its
            // absence is ordinary — a source with nothing playing yields video
            // alone — but when someone expects their audio to be shared and it
            // is not, this row is where they find out.
            Tooltip(
              message: 'System audio is being shared',
              child: Icon(
                Icons.volume_up,
                size: 15,
                color: colors.voiceControlIcon,
              ),
            ),
            const SizedBox(width: 6),
          ],
          IconButton(
            onPressed: onStop,
            iconSize: 18,
            tooltip: 'Stop sharing this',
            icon: Icon(Icons.stop_circle, color: colors.voiceControlDanger),
          ),
        ],
      ),
    );
  }
}
