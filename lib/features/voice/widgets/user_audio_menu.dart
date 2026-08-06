import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../call_controller_provider.dart';
import '../voice_participant.dart';
import '../voice_prefs_controller.dart';
import '../voice_prefs_state.dart';

/// Per-user audio controls: how loud this person is, just for you.
///
/// Nothing here is sent anywhere. Turning someone down is a property of your
/// playback, and the homeserver never learns about it.
///
/// Two independent volumes, as Discord has: someone's voice and the audio of
/// the screen they are sharing are different things you want at different
/// levels, and a single slider forces a compromise between hearing them speak
/// and hearing what they are showing.
class UserAudioMenu extends ConsumerWidget {
  const UserAudioMenu({super.key, required this.participant});

  final VoiceParticipant participant;

  static Future<void> show(
    BuildContext context,
    VoiceParticipant participant,
  ) => showDialog(
    context: context,
    builder: (context) => UserAudioMenu(participant: participant),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefs = ref.watch(voicePrefsProvider).forUser(participant.userId);
    final notifier = ref.read(voicePrefsProvider.notifier);
    final hasScreenAudio = ref
        .watch(callControllerProvider)
        .hasScreenAudio(participant.userId);

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Row(
        children: [
          MxAvatar(
            name: participant.displayName,
            seed: participant.userId,
            mxcUri: participant.avatarMxc,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              participant.displayName,
              style: context.text.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final deviceId in participant.deviceIds) ...[
              // Only labelled when there is more than one: naming the device is
              // noise for the overwhelmingly common single-device case, and
              // essential when someone is connected twice with two different
              // microphones.
              if (participant.deviceIds.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Device $deviceId',
                    style: context.text.fieldLabel,
                  ),
                ),
              _VolumeSlider(
                label: 'Voice',
                icon: Icons.mic,
                value: prefs.forDevice(deviceId).micVolume,
                enabled: !prefs.locallyMuted,
                // Live while dragging, written once on release: the audio has
                // to follow the thumb, but SharedPreferences must not be hit
                // at 60Hz.
                onChanged: (value) => notifier.setUserMicVolume(
                  participant.userId,
                  deviceId,
                  value,
                  commit: false,
                ),
                onChangeEnd: (value) => notifier.setUserMicVolume(
                  participant.userId,
                  deviceId,
                  value,
                ),
              ),
              const SizedBox(height: 12),
              _VolumeSlider(
                label: 'Screen Share Audio',
                icon: Icons.volume_up,
                value: prefs.forDevice(deviceId).screenVolume,
                enabled: !prefs.locallyMuted && hasScreenAudio,
                disabledHint: hasScreenAudio
                    ? null
                    : 'This person is not sharing audio right now.',
                onChanged: (value) => notifier.setUserScreenVolume(
                  participant.userId,
                  deviceId,
                  value,
                  commit: false,
                ),
                onChangeEnd: (value) => notifier.setUserScreenVolume(
                  participant.userId,
                  deviceId,
                  value,
                ),
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: prefs.locallyMuted,
              activeThumbColor: colors.voiceMutedIcon,
              title: Text('Mute locally', style: context.text.messageBody),
              subtitle: Text(
                'Only affects what you hear.',
                style: context.text.timestamp,
              ),
              onChanged: (muted) =>
                  notifier.setUserLocallyMuted(participant.userId, muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => notifier.resetUser(participant.userId),
          child: Text('Reset', style: TextStyle(color: colors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Done', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    this.disabledHint,
  });

  final String label;
  final IconData icon;
  final double value;
  final bool enabled;
  final String? disabledHint;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: enabled ? colors.textMuted : colors.textFaint,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label.toUpperCase(), style: context.text.fieldLabel),
            ),
            Text('${(value * 100).round()}%', style: context.text.timestamp),
          ],
        ),
        Slider(
          value: value.clamp(0.0, kMaxVolume),
          // 200% rather than 100%: a quiet speaker is a real problem, and
          // boosting them is the whole reason a per-user control beats the
          // system mixer.
          max: kMaxVolume,
          // No `divisions`: continuous. The controller coalesces the resulting
          // burst of changes so the native audio channel is not flooded.
          activeColor: colors.volumeSliderActive,
          inactiveColor: colors.volumeSliderTrack,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
        ),
        if (!enabled && disabledHint != null)
          Text(disabledHint!, style: context.text.timestamp),
      ],
    );
  }
}
