// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/app_tooltip.dart';
import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import '../call_controller_provider.dart';
import '../livekit_call_controller.dart';
import '../voice_prefs_controller.dart';
import '../wayland_screencast.dart';
import '../../../core/util/display_name.dart';
import 'screen_share_menu.dart';
import 'screen_source_picker.dart';

/// Connection status and call controls, above the user footer.
///
/// Collapses to nothing when not in a call, so the sidebar is unchanged for
/// anyone who never joins one.
class VoiceStatusFooter extends ConsumerWidget {
  const VoiceStatusFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(callControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.status == CallStatus.idle) {
          return const SizedBox.shrink();
        }

        final colors = context.colors;
        final (label, color) = switch (controller.status) {
          CallStatus.connected => ('Voice Connected', colors.voiceConnected),
          CallStatus.joining => ('Connecting…', colors.voiceConnecting),
          CallStatus.leaving => ('Disconnecting…', colors.voiceConnecting),
          CallStatus.failed => (
            controller.error ?? 'Connection failed',
            colors.voiceError,
          ),
          CallStatus.idle => ('', colors.textMuted),
        };

        final roomName = _roomName(ref, controller.roomId);

        return Container(
          color: colors.voiceControlBar,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    controller.status == CallStatus.failed
                        ? Icons.error_outline
                        : Icons.signal_cellular_alt,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    // The detail hangs off a tooltip rather than the line
                    // itself: this row is one clipped line in a narrow
                    // sidebar, and a sentence long enough to say which half of
                    // the stack gave up would be ellipsised to nothing.
                    child: AppTooltip(
                      message: controller.errorDetail ?? label,
                      child: Text(
                        label,
                        style: context.text.subtitle.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (roomName != null) ...[
                const SizedBox(height: 2),
                Text(
                  roomName,
                  style: context.text.timestamp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              _Controls(controller: controller),
            ],
          ),
        );
      },
    );
  }

  String? _roomName(WidgetRef ref, String? roomId) {
    if (roomId == null) return null;
    final room = ref.read(clientProvider).getRoomById(roomId);
    final name = room?.getLocalizedDisplayname();
    return name == null ? null : displaySafeName(name);
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.controller});

  final LiveKitCallController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final live = controller.isInCall;

    return Row(
      children: [
        Expanded(
          child: _ControlButton(
            icon: controller.cameraOn ? Icons.videocam : Icons.videocam_off,
            tooltip: controller.cameraOn ? 'Turn off camera' : 'Turn on camera',
            color: controller.cameraOn
                ? colors.voiceControlIconActive
                : colors.voiceControlIcon,
            onPressed: live
                ? () => controller.setCameraEnabled(!controller.cameraOn)
                : null,
          ),
        ),
        Expanded(
          child: _ControlButton(
            icon: controller.screenSharing
                ? Icons.stop_screen_share
                : Icons.screen_share,
            tooltip: switch (controller.shares.length) {
              0 => 'Share your screen',
              1 => 'Sharing 1 screen',
              final count => 'Sharing $count screens',
            },
            color: controller.screenSharing
                ? colors.voiceControlIconActive
                : colors.voiceControlIcon,
            onPressed: live ? () => _onScreenShare(context, ref) : null,
          ),
        ),
        Expanded(
          child: _ControlButton(
            icon: controller.micMuted ? Icons.mic_off : Icons.mic,
            tooltip: controller.micMuted ? 'Unmute' : 'Mute',
            color: controller.micMuted
                ? colors.voiceMutedIcon
                : colors.voiceControlIcon,
            onPressed: live
                ? () => controller.setMicMuted(!controller.micMuted)
                : null,
          ),
        ),
        Expanded(
          child: _ControlButton(
            icon: controller.deafened ? Icons.headset_off : Icons.headset,
            tooltip: controller.deafened ? 'Undeafen' : 'Deafen',
            color: controller.deafened
                ? colors.voiceDeafenedIcon
                : colors.voiceControlIcon,
            onPressed: live
                ? () => controller.setDeafened(!controller.deafened)
                : null,
          ),
        ),
        Expanded(
          child: _ControlButton(
            icon: Icons.call_end,
            tooltip: 'Disconnect',
            color: colors.voiceControlDanger,
            onPressed: controller.status == CallStatus.leaving
                ? null
                : () => controller.leave(),
          ),
        ),
      ],
    );
  }

  /// The screen-share button.
  ///
  /// Nothing shared yet means there is nothing to choose between: go straight
  /// to the picker. Once something is up, the button opens the list instead —
  /// with several shares running, "stop sharing" is no longer a question with
  /// one answer.
  Future<void> _onScreenShare(BuildContext context, WidgetRef ref) async {
    if (controller.screenSharing) {
      await ScreenShareMenu.show(
        context,
        onAddShare: () => _pickAndShare(context, ref),
      );
      return;
    }
    await _pickAndShare(context, ref);
  }

  Future<void> _pickAndShare(BuildContext context, WidgetRef ref) async {
    // On a Linux Wayland session flutter_webrtc's capturer must not be
    // touched: its bundled libwebrtc only knows X11, gets no capturer at
    // all here, and listing sources dereferences that null capturer, which
    // takes the whole app down. The desktop's portal picks instead, in its
    // own dialog; see `WaylandScreencast`.
    if (WaylandScreencast.applies) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (await WaylandScreencast.isAvailable()) {
        await controller.startWaylandScreenShare();
      } else {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Screen sharing on Wayland needs xdg-desktop-portal with '
              'PipeWire, and this build has no support for it.',
            ),
          ),
        );
      }
      return;
    }

    // Ours, not livekit_client's. Theirs is hard-coded white, offers every
    // shell window Windows will admit to, and returns an id with the window
    // title thrown away — see `ScreenSourcePicker` for the full account.
    final source = await ScreenSourcePicker.show(context);
    if (source == null) return;

    // Whether to include system audio is a stored setting rather than another
    // prompt here: it can cause echo, so it deserves a considered choice made
    // once in settings, not a checkbox clicked in a hurry.
    await controller.startScreenShare(
      source.id,
      withSystemAudio: ref.read(voicePrefsProvider).shareSystemAudio,
      name: source.name,
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppTooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 18,
          color: onPressed == null ? context.colors.textFaint : color,
        ),
        visualDensity: VisualDensity.compact,
        splashRadius: 18,
      ),
    );
  }
}
