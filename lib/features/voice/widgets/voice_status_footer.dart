import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../call_controller_provider.dart';
import '../livekit_call_controller.dart';
import '../voice_prefs_controller.dart';

/// Connection status and call controls, above the user footer.
///
/// Collapses to nothing when not in a call, so the sidebar is unchanged for
/// anyone who never joins one. This is where Discord puts it.
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
    return room?.getLocalizedDisplayname();
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
            tooltip: controller.screenSharing
                ? 'Stop sharing'
                : 'Share your screen',
            color: controller.screenSharing
                ? colors.voiceControlIconActive
                : colors.voiceControlIcon,
            onPressed: live ? () => _toggleScreenShare(context, ref) : null,
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

  Future<void> _toggleScreenShare(BuildContext context, WidgetRef ref) async {
    if (controller.screenSharing) {
      await controller.stopScreenShare();
      return;
    }

    // livekit_client ships this picker with live thumbnails and screen/window
    // tabs. Reimplementing it would gain nothing today.
    //
    // Marked experimental upstream, so it may change or disappear in a future
    // release. Contained deliberately: it is used in exactly this one place and
    // returns nothing but a source id, so replacing it means writing a dialog
    // that returns a string — no other code would have to change.
    // ignore: experimental_member_use
    final sourceId = await lk.ScreenSelectDialog.show(context);
    if (sourceId == null) return;

    // Whether to include system audio is a stored setting rather than another
    // prompt here: it can cause echo, so it deserves a considered choice made
    // once in settings, not a checkbox clicked in a hurry.
    await controller.startScreenShare(
      sourceId,
      withSystemAudio: ref.read(voicePrefsProvider).shareSystemAudio,
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
    return Tooltip(
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
