// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/audio_level_sampler.dart';
import 'package:hardline/features/voice/noise_gate.dart';

/// The sampler needs a real `lk.Room` to measure anything, which needs an SFU.
/// What can be tested without one is its lifecycle — and that is where the bug
/// was: `start` did not await `stop`, so `stop`'s tail landed after `start` had
/// finished and wiped the room out from under the timer. Every tick then found
/// no track, and the meter sat on "join a call" for the whole call while
/// nothing in the log said why.
void main() {
  late List<MicLevel> levels;
  late List<Set<String>> audible;
  late AudioLevelSampler sampler;

  setUp(() {
    levels = [];
    audible = [];
    sampler = AudioLevelSampler(
      readGateSettings: () =>
          const GateSettings(enabled: false, thresholdDb: -65, gainDb: 0),
      onMicLevel: levels.add,
      onAudible: audible.add,
    );
  });

  tearDown(() => sampler.dispose());

  test('stopping reports nothing measured and nobody audible', () async {
    await sampler.stop();

    expect(levels, [const MicLevel.none()]);
    expect(audible, [const <String>{}]);
  });

  // `stop` is async and its tail resets the room. If `start` does not wait for
  // it, that reset arrives after the timer is already running.
  test('stopping settles before anything else is asked of it', () async {
    final stopping = sampler.stop();
    expect(levels, isEmpty, reason: 'the tail has not run yet');

    await stopping;
    expect(levels, isNotEmpty);
  });

  test('stopping twice is harmless', () async {
    await sampler.stop();
    await sampler.stop();

    expect(levels.every((level) => level == const MicLevel.none()), isTrue);
  });

  test('disposing is a stop', () async {
    await sampler.dispose();

    expect(levels, isNotEmpty);
    expect(levels.last, const MicLevel.none());
  });
}
