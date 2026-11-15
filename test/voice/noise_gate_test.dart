// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/mic_tap.dart';
import 'package:hardline/features/voice/noise_gate.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1);
  DateTime at(int ms) => start.add(Duration(milliseconds: ms));

  group('opening and closing', () {
    test('starts shut, so a silent room is not transmitted', () {
      final gate = NoiseGate(thresholdDb: -55);

      expect(gate.update(-70, at(0)), isFalse);
      expect(gate.isOpen, isFalse);
    });

    // A gate that waited would clip the first syllable of every sentence,
    // which is the one thing that makes a gate obvious to the people
    // listening.
    test('opens on the first sample over the line, with no delay', () {
      final gate = NoiseGate(thresholdDb: -55);

      expect(gate.update(-40, at(0)), isTrue);
    });

    // The constant was once raised to 600ms while the constructor went on
    // defaulting to 400, so the app ran on the old hold and the measurement
    // that prompted the change kept failing.
    test('holds for kGateHold unless told otherwise', () {
      final gate = NoiseGate(thresholdDb: -55);

      expect(gate.hold, kGateHold);
      expect(gate.update(-40, at(0)), isTrue);
      expect(gate.update(-70, at(kGateHold.inMilliseconds - 1)), isTrue);
      expect(gate.update(-70, at(kGateHold.inMilliseconds)), isFalse);
    });

    test('stays open through a pause shorter than the hold', () {
      final gate = NoiseGate(
        thresholdDb: -55,
        hold: const Duration(milliseconds: 400),
      );
      gate.update(-40, at(0));

      expect(gate.update(-70, at(100)), isTrue);
      expect(gate.update(-70, at(399)), isTrue);
    });

    test('closes once the hold has passed entirely below', () {
      final gate = NoiseGate(
        thresholdDb: -55,
        hold: const Duration(milliseconds: 400),
      );
      gate.update(-40, at(0));

      expect(gate.update(-70, at(400)), isFalse);
    });

    // The pause inside a sentence is the case a gate has to get right: each
    // word restarts the clock, so the gap between them never accumulates into
    // a close.
    test('a word restarts the hold', () {
      final gate = NoiseGate(
        thresholdDb: -55,
        hold: const Duration(milliseconds: 400),
      );

      gate.update(-40, at(0));
      expect(gate.update(-70, at(300)), isTrue);
      expect(gate.update(-40, at(350)), isTrue);
      expect(gate.update(-70, at(650)), isTrue, reason: 'only 300ms since');
      expect(gate.update(-70, at(751)), isFalse);
    });

    test('exactly at the threshold counts as speech', () {
      final gate = NoiseGate(thresholdDb: -55);

      expect(gate.update(-55, at(0)), isTrue);
    });

    test('reopens after closing', () {
      final gate = NoiseGate(
        thresholdDb: -55,
        hold: const Duration(milliseconds: 400),
      );
      gate.update(-40, at(0));
      gate.update(-70, at(500));

      expect(gate.update(-40, at(600)), isTrue);
    });
  });

  // The gate shuts the microphone by disabling the track it is also measuring.
  // If disabling it zeroes the reading — platform behaviour we do not control —
  // a closed gate would see silence forever and never reopen, leaving somebody
  // inaudible with a microphone that looks live. These are the tests that say
  // it fails the other way instead.
  // The trim exists to move a quiet microphone into the part of the scale the
  // threshold can work in. Comparing the threshold against the *untrimmed*
  // reading would be comparing against the very number the trim was there to
  // fix, so the order is load-bearing rather than incidental.
  //
  // `AudioLevelSampler` adds the gain before calling `update`; this is the
  // arithmetic that makes that the right thing to do.
  group('the trim applies before the line', () {
    test('a voice below the line is above it once trimmed', () {
      final gate = NoiseGate(thresholdDb: -55);

      // What a dynamic microphone actually measures on this scale.
      const speech = -90.0;
      expect(gate.update(speech, at(0)), isFalse, reason: 'untrimmed');

      const trim = 40.0;
      expect(gate.update(speech + trim, at(100)), isTrue, reason: 'trimmed');
    });

    test('the trim lifts the noise floor too, so the line still separates', () {
      final gate = NoiseGate(thresholdDb: -55);
      const trim = 40.0;

      // A room at -100 and speech at -90 are ten decibels apart before and
      // after: a trim moves both, which is why the line has to be set after it.
      expect(gate.update(-100 + trim, at(0)), isFalse, reason: 'room');
      expect(gate.update(-90 + trim, at(100)), isTrue, reason: 'speech');
    });
  });

  // The bug that made turning the gate on a one-way trip to silence. The trim
  // was being added to *every* reading including the absolute floor, so a
  // microphone that had stopped reporting looked merely quiet (-100 + 40 = -60)
  // rather than absent. The fail-safe waits for the floor exactly, so it never
  // fired, and a gate that had closed stayed closed for the rest of the call.
  // The gate used to give up on its own: held shut for three seconds with the
  // level pinned at the floor, it concluded it had blinded itself and reopened
  // for good. That is gone, because "pinned at the floor" is what a
  // hardware-muted headset, a virtual cable and every vendor noise suppressor
  // emit — so the guard fired on ordinary silence and quietly stopped gating.
  //
  // A gate that will not open is a failure somebody can see and switch off. A
  // gate that stopped gating without saying so is not.
  group('silence never makes the gate give up', () {
    test('a floor for ever keeps it shut', () {
      final gate = NoiseGate(
        thresholdDb: -55,
        hold: const Duration(milliseconds: 400),
      );

      gate.update(-40, at(0));
      expect(gate.update(MicTap.silenceDb, at(500)), isFalse);
      for (var t = 1000; t < 60000; t += 1000) {
        expect(gate.update(MicTap.silenceDb, at(t)), isFalse, reason: 'at $t');
      }
    });

    test('and it still opens the moment somebody speaks', () {
      final gate = NoiseGate(thresholdDb: -55);

      expect(gate.update(MicTap.silenceDb, at(0)), isFalse);
      for (var t = 1000; t < 30000; t += 1000) {
        gate.update(MicTap.silenceDb, at(t));
      }
      expect(gate.update(-40, at(30000)), isTrue);
    });
  });

  group('MicLevel', () {
    test('nothing measured is nothing measured', () {
      const none = MicLevel.none();

      expect(none.db, MicTap.silenceDb);
      expect(none.measured, isFalse);
      expect(none.gateOpen, isFalse);
      expect(none.gateActive, isFalse);
    });

    // The meter draws an empty bar for one and says "join a call" for the
    // other, so a reading of silence must not be mistaken for no reading.
    test('silence is not the same as nothing to read', () {
      const silent = MicLevel(
        db: MicTap.silenceDb,
        speaking: false,
        gateOpen: false,
        gateActive: true,
      );

      expect(silent.measured, isTrue);
      expect(silent, isNot(const MicLevel.none()));
    });

    test('equality is by value', () {
      expect(
        const MicLevel(
          db: -40,
          speaking: true,
          gateOpen: true,
          gateActive: true,
        ),
        const MicLevel(
          db: -40,
          speaking: true,
          gateOpen: true,
          gateActive: true,
        ),
      );
      expect(
        const MicLevel(
          db: -40,
          speaking: true,
          gateOpen: true,
          gateActive: true,
        ),
        isNot(
          const MicLevel(
            db: -40,
            speaking: true,
            gateOpen: false,
            gateActive: true,
          ),
        ),
      );
    });

    // The bug that lit an avatar for the whole of a call. `gateOpen` answers
    // "is anything being withheld", which with the gate switched off is
    // permanently no — so a ring wired to it never went out. They are separate
    // fields because they are separate questions.
    test('speaking and transmitting are not the same thing', () {
      const quietButUngated = MicLevel(
        db: -95,
        speaking: false,
        gateOpen: true,
        gateActive: false,
      );

      expect(quietButUngated.gateOpen, isTrue, reason: 'nothing withheld');
      expect(quietButUngated.speaking, isFalse, reason: 'but not speaking');
    });
  });
}
