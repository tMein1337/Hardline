// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../hotkeys/hotkey_provider.dart';
import '../../hotkeys/hotkeys_controller.dart';
import '../../hotkeys/hotkey.dart';
import '../../hotkeys/hotkey_action.dart';
import '../../voice/audio_devices_provider.dart';
import '../../voice/call_controller_provider.dart';
import '../../voice/voice_prefs_controller.dart';
import '../../voice/voice_prefs_state.dart';
import '../../voice/widgets/mic_level_meter.dart';
import '../widgets/hotkey_row.dart';
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
                  'Changing the microphone during a call reopens it, so others '
                  'may miss a moment. Changing the output is silent. On the '
                  'system default, Windows may move you to a different device '
                  'mid-call without saying so — naming one here avoids that.',
                  style: context.text.timestamp,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const SettingsLabel('Microphone breakpoint'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MicLevelMeter(thresholdDb: prefs.micThresholdDb),
              const SizedBox(height: 12),
              SettingsHint(
                // One sentence. This was six lines, which is longer than
                // anybody reads from a tooltip that appeared under their
                // pointer — the rest of it is on the page below, where it can
                // be read at leisure instead of raced.
                message:
                    'Moves the reading, not your voice: raise it until talking '
                    'fills about two thirds of the bar.',
                child: Row(
                  children: [
                    SizedBox(
                      width: 74,
                      child: Text('Gain', style: context.text.subtitle),
                    ),
                    Expanded(
                      child: Slider(
                        value: prefs.micGainDb.clamp(0.0, kMaxMicGainDb),
                        max: kMaxMicGainDb,
                        divisions: kMaxMicGainDb.round(),
                        label: '+${prefs.micGainDb.round()} dB',
                        onChanged: (value) => ref
                            .read(voicePrefsProvider.notifier)
                            .setMicGainDb(value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '+${prefs.micGainDb.round()} dB',
                        style: context.text.messageBody,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Gain moves the measurement only — nobody hears you any '
                'louder, and it cannot make you louder to them. A quiet '
                'microphone can read far below where the breakpoint is '
                'allowed to go, which is what this is for: bring the reading '
                'up first, then set the breakpoint underneath your voice.',
                style: context.text.timestamp,
              ),
              const SizedBox(height: 12),
              SettingsHint(
                message:
                    'Where you stop being background noise and start being '
                    'speech. Talk normally and put it between the two.',
                child: Row(
                  children: [
                    SizedBox(
                      width: 74,
                      child: Text('Breakpoint', style: context.text.subtitle),
                    ),
                    Expanded(
                      child: Slider(
                        value: prefs.micThresholdDb.clamp(
                          kMinThresholdDb,
                          kMaxThresholdDb,
                        ),
                        min: kMinThresholdDb,
                        max: kMaxThresholdDb,
                        // One decibel a step. Finer would be false precision on a
                        // reading taken from FFT bands, which is relative and
                        // not calibrated.
                        divisions: (kMaxThresholdDb - kMinThresholdDb).round(),
                        label: '${prefs.micThresholdDb.round()} dB',
                        onChanged: (value) => ref
                            .read(voicePrefsProvider.notifier)
                            .setMicThresholdDb(value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${prefs.micThresholdDb.round()} dB',
                        style: context.text.messageBody,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
              const SettingsDivider(),
              SettingsSwitchTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.noiseGate,
                title: 'Stop sending audio below the breakpoint',
                // Kept on the page rather than moved to a hover. Everything
                // else here explains a control; this one says what happens if
                // you get it wrong, and being inaudible is the one failure you
                // cannot notice from this end.
                subtitle:
                    'Keyboard noise, a fan and breathing never reach the call. '
                    'Set the breakpoint too high and people stop hearing you — '
                    'which is not something you can notice from this end, so '
                    'watch the meter while you talk before turning it on.',
                onChanged: (value) =>
                    ref.read(voicePrefsProvider.notifier).setNoiseGate(value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SettingsLabel('Screen sharing'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SettingsSwitchTile(
            value: prefs.shareSystemAudio,
            title: 'Share system audio when sharing a screen',
            subtitle:
                'Sends the audio of what you share. On speakers this can echo '
                'the others back to them — headphones avoid that.',
            onChanged: (value) => ref
                .read(voicePrefsProvider.notifier)
                .setShareSystemAudio(value),
          ),
        ),

        const SizedBox(height: 24),
        const SettingsLabel('Joining'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SettingsSwitchTile(
            value: prefs.doubleClickToJoin,
            title: 'Double-click a channel to join its call',
            subtitle:
                'Only when a call is already running there. Off by default '
                'because binding a double-click makes every single click on a '
                'channel wait to see whether a second one is coming, which '
                'makes switching rooms feel slow.',
            onChanged: (value) => ref
                .read(voicePrefsProvider.notifier)
                .setDoubleClickToJoin(value),
          ),
        ),

        const SizedBox(height: 24),
        const SettingsLabel('Shortcuts'),
        const _CallHotkeys(),

        const SizedBox(height: 24),
        const SettingsLabel('Diagnostics'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SettingsSwitchTile(
            value: prefs.verboseCallLog,
            onChanged: (value) =>
                ref.read(voicePrefsProvider.notifier).setVerboseCallLog(value),
            title: 'Log call connection details',
            // On the page rather than behind a hover, because somebody reads
            // this while a call is already refusing to connect — which is
            // exactly when a control whose meaning is hidden is no use.
            subtitle:
                'Prints what the call server offers and whether the media '
                'connection is ever made. Off by default: it is several lines '
                'a second during a call. Turn it on when a call will not '
                'connect — the error alone cannot say whether the problem is '
                'the server, the network between you, or a firewall.',
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
                items: [
                  // A real entry rather than a `hint`. It was a hint, which
                  // meant two things went wrong at once: it drew in the muted
                  // hint style while every device below it drew in the body
                  // style — so "System default" looked disabled — and there
                  // was no way to choose it, because nothing in a dropdown can
                  // select the hint. Every fresh install starts here, with
                  // nothing remembered, and could leave but never come back.
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      'System default',
                      style: context.text.messageBody,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                  // Null is the system-default entry, and `setInputDevice`
                  // already takes a nullable ref: forgetting the remembered
                  // device *is* going back to the default.
                  if (deviceId == null) {
                    onChanged(null);
                    return;
                  }
                  onChanged(devices.firstWhere((d) => d.deviceId == deviceId));
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// The global chords that work from inside a game.
///
/// Unbound out of the box: see [kDefaultHotkeys] for why guessing at
/// Alt+M on somebody's behalf would be taking a chord away from whatever
/// already used it.
class _CallHotkeys extends ConsumerWidget {
  const _CallHotkeys();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = ref.watch(hotkeysProvider);
    final notifier = ref.read(hotkeysProvider.notifier);
    final binder = ref.watch(hotkeyBinderProvider);

    return SettingsCard(
      // Listened to, not read once: Windows answers after the rebuild that
      // binding the chord causes, so the refusal would otherwise only show up
      // whenever something else next rebuilt this card.
      child: ValueListenableBuilder(
        valueListenable: binder.rejected,
        builder: (context, rejected, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'These work while another program has the foreground, which is '
              'the point of them — the app does not need to be in front, or '
              'even visible. They do nothing unless you are in a call.',
              style: context.text.timestamp,
            ),
            const SizedBox(height: 8),
            for (final (index, action) in HotkeyAction.alwaysOn.indexed) ...[
              if (index > 0) const SettingsDivider(),
              HotkeyRow(
                key: Key('hotkey_${action.name}'),
                label: action.label,
                hotkey: bindings[action] ?? const Hotkey.none(),
                // Named by the conflict rather than a generic refusal: two
                // actions on one chord means only one of them ever fires,
                // which reads exactly like the second binding having silently
                // failed.
                problem: hotkeyProblem(bindings, rejected, action),
                onChanged: (hotkey) =>
                    notifier.setBinding(action, hotkey.isBound ? hotkey : null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
