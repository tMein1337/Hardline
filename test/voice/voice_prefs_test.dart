// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/audio_devices_provider.dart';
import 'package:hardline/features/voice/voice_prefs_state.dart';

void main() {
  group('VoicePrefsState', () {
    test('round-trips through JSON', () {
      const state = VoicePrefsState(
        selfMuted: true,
        deafened: true,
        inputDevice: AudioDeviceRef(deviceId: 'in-1', label: 'TONOR mic'),
        outputDevice: AudioDeviceRef(deviceId: 'out-1', label: 'Headphones'),
        users: {
          '@bob:example.org': VoiceUserPrefs(
            locallyMuted: true,
            devices: {'PHONE': VoiceDeviceAudio(micVolume: 0.4)},
          ),
        },
      );

      expect(VoicePrefsState.fromJson(state.toJson()), state);
    });

    // The whole point of keying volume by device: one person's laptop mic and
    // desk mic need different gains, and switching between them must not
    // require re-adjusting.
    test('volumes are kept separately per device of the same person', () {
      const state = VoicePrefsState(
        users: {
          '@bob:example.org': VoiceUserPrefs(
            devices: {
              'LAPTOP': VoiceDeviceAudio(micVolume: 1.8),
              'DESKTOP': VoiceDeviceAudio(micVolume: 0.5),
            },
          ),
        },
      );

      expect(state.audioFor('@bob:example.org', 'LAPTOP').micVolume, 1.8);
      expect(state.audioFor('@bob:example.org', 'DESKTOP').micVolume, 0.5);
    });

    // Inheriting a boost calibrated for a different microphone is exactly the
    // mis-calibration the per-device design exists to avoid.
    test('an unknown device starts neutral rather than inheriting', () {
      const state = VoicePrefsState(
        users: {
          '@bob:example.org': VoiceUserPrefs(
            devices: {'LAPTOP': VoiceDeviceAudio(micVolume: 1.9)},
          ),
        },
      );

      expect(state.audioFor('@bob:example.org', 'BRAND_NEW').micVolume, 1.0);
    });

    // Muting is a statement about the person, so it must not be lost when they
    // appear from a device we have never seen.
    test('a local mute applies on every device of that person', () {
      const state = VoicePrefsState(
        users: {'@bob:example.org': VoiceUserPrefs(locallyMuted: true)},
      );

      expect(state.forUser('@bob:example.org').locallyMuted, isTrue);
      expect(state.audioFor('@bob:example.org', 'ANY_DEVICE').micVolume, 1.0);
    });

    // Otherwise the blob grows one entry per person ever met in a call.
    test('users and devices back at their defaults are not written', () {
      const state = VoicePrefsState(
        users: {
          '@bob:example.org': VoiceUserPrefs(),
          '@carol:example.org': VoiceUserPrefs(
            devices: {
              'IDLE': VoiceDeviceAudio(),
              'TUNED': VoiceDeviceAudio(micVolume: 0.5),
            },
          ),
        },
      );

      final users = state.toJson()['users']! as Map;
      expect(users.keys, ['@carol:example.org']);
      final devices = (users['@carol:example.org'] as Map)['devices'] as Map;
      expect(devices.keys, ['TUNED']);
    });

    // A hand-edited or corrupted value must not be applied as a 50x gain the
    // moment a call connects.
    test('volumes are clamped at parse time', () {
      final state = VoicePrefsState.fromJson({
        'users': {
          '@loud:example.org': {
            'devices': {
              'D1': {'mic': 50, 'screen': -3},
            },
          },
        },
      });

      expect(state.audioFor('@loud:example.org', 'D1').micVolume, kMaxVolume);
      expect(state.audioFor('@loud:example.org', 'D1').screenVolume, 0.0);
    });

    // v1 stored volumes directly on the user. Those were calibrated against
    // "whichever device that person happened to be on" and cannot be
    // attributed to one, so they are dropped — but the mute still means what
    // it always did.
    test('a v1 blob keeps the mute and drops the unattributable volumes', () {
      final state = VoicePrefsState.fromJson({
        'version': 1,
        'users': {
          '@bob:example.org': {'mic': 0.4, 'screen': 1.5, 'muted': true},
        },
      });

      expect(state.forUser('@bob:example.org').locallyMuted, isTrue);
      expect(state.forUser('@bob:example.org').devices, isEmpty);
    });

    test('malformed JSON degrades to defaults instead of throwing', () {
      final state = VoicePrefsState.fromJson({
        'selfMuted': 'yes',
        'users': 'not a map',
        'inputDevice': 42,
      });

      expect(state.selfMuted, isFalse);
      expect(state.users, isEmpty);
      expect(state.inputDevice, isNull);
    });

    test('unknown users fall back to defaults without null checks', () {
      const state = VoicePrefsState();
      expect(state.forUser('@nobody:example.org'), const VoiceUserPrefs());
    });
  });

  group('resolveDevice', () {
    const tonor = AudioDeviceRef(deviceId: 'id-a', label: 'TONOR TD510');
    const cable = AudioDeviceRef(deviceId: 'id-b', label: 'CABLE Output');

    test('matches on device id', () {
      expect(resolveDevice(tonor, [cable, tonor]), tonor);
    });

    // A device moved to another USB port keeps its name but not its id.
    // Without this the user would be silently thrown back onto whatever
    // enumerates first, which is the bug this whole feature exists to fix.
    test('falls back to matching on label when the id changed', () {
      const movedTonor = AudioDeviceRef(
        deviceId: 'id-new',
        label: 'TONOR TD510',
      );
      expect(resolveDevice(tonor, [cable, movedTonor]), movedTonor);
    });

    test('returns null when the device is gone entirely', () {
      expect(resolveDevice(tonor, [cable]), isNull);
    });

    test('returns null when nothing was remembered', () {
      expect(resolveDevice(null, [cable]), isNull);
    });
  });
}
