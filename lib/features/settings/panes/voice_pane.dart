import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../voice/audio_devices_provider.dart';
import '../../voice/call_controller_provider.dart';
import '../../voice/voice_prefs_controller.dart';
import '../../voice/voice_prefs_state.dart';
import '../widgets/settings_layout.dart';

/// Voice & video settings: which microphone to capture and where to play.
///
/// This is not a nicety. livekit_client picks the *first enumerated* device
/// rather than the operating system default, which on Windows is regularly a
/// virtual cable — audio then goes to and comes from somewhere the user is not,
/// while every other part of the stack reports success. Being able to choose,
/// and having that choice remembered, is what makes calls work at all on a
/// machine with more than one sound device.
class VoicePane extends ConsumerWidget {
  const VoicePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(audioDevicesProvider);
    final prefs = ref.watch(voicePrefsProvider);

    return SettingsPane(
      title: 'Voice & Video',
      children: [
        devices.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SettingsCard(
            child: Text(
              'Could not read the audio devices.\n$error',
              style: context.text.subtitle,
            ),
          ),
          data: (data) => SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DeviceSection(
                  label: 'Microphone',
                  icon: Icons.mic,
                  devices: data.inputs.items,
                  selected: resolveDevice(prefs.inputDevice, data.inputs.items),
                  onChanged: (device) async {
                    await ref
                        .read(voicePrefsProvider.notifier)
                        .setInputDevice(device);
                    await ref.read(callControllerProvider).applyAudioDevices();
                  },
                ),
                const SizedBox(height: 16),
                _DeviceSection(
                  label: 'Output',
                  icon: Icons.headphones,
                  devices: data.outputs.items,
                  selected: resolveDevice(
                    prefs.outputDevice,
                    data.outputs.items,
                  ),
                  onChanged: (device) async {
                    await ref
                        .read(voicePrefsProvider.notifier)
                        .setOutputDevice(device);
                    await ref.read(callControllerProvider).applyAudioDevices();
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Changing the microphone during a call republishes it, so '
                  'others may hear a brief gap.',
                  style: context.text.timestamp,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const SettingsLabel('Screen sharing'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            value: prefs.shareSystemAudio,
            title: Text(
              'Share system audio when sharing a screen',
              style: context.text.messageBody,
            ),
            subtitle: Text(
              'Sends the audio of what you share. On speakers this can echo '
              'the others back to them — headphones avoid that.',
              style: context.text.timestamp,
            ),
            onChanged: (value) =>
                ref.read(voicePrefsProvider.notifier).setShareSystemAudio(value),
          ),
        ),
      ],
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.label,
    required this.icon,
    required this.devices,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<AudioDeviceRef> devices;
  final AudioDeviceRef? selected;
  final ValueChanged<AudioDeviceRef?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(label.toUpperCase(), style: context.text.fieldLabel),
          ],
        ),
        const SizedBox(height: 6),
        if (devices.isEmpty)
          Text(
            'No $label device found.',
            style: context.text.subtitle.copyWith(color: colors.voiceError),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: colors.inputBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.inputBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                dropdownColor: colors.floatingSurface,
                // Keyed by device id rather than the object: the list is
                // rebuilt on every hotplug, so identity comparison would drop
                // the selection whenever a device appears or disappears.
                value: selected?.deviceId,
                hint: Text(
                  'System default (currently unreliable)',
                  style: context.text.subtitle,
                ),
                items: [
                  for (final device in devices)
                    DropdownMenuItem(
                      value: device.deviceId,
                      child: Text(
                        device.label.isEmpty ? device.deviceId : device.label,
                        style: context.text.messageBody,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (deviceId) {
                  if (deviceId == null) return;
                  onChanged(
                    devices.firstWhere((d) => d.deviceId == deviceId),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
