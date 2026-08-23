// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/mic_tap.dart';

void main() {
  /// What the visualizer emits for a given level in decibels.
  ///
  /// Its own curve, `sqrt(1 - |dB| / 100)`, clamped the way its C++ clamps it.
  /// Written out here rather than reusing the production inverse so the two are
  /// independent: one mistake copied into both would test nothing.
  double bandAt(double db) =>
      math.sqrt(1 - math.min(100, math.max(30, -db)) / 100);

  group('recovering decibels', () {
    // The whole reason `MicTap` does arithmetic at all. The visualizer hands
    // back a squashed band magnitude; undoing its curve is what makes a dB
    // slider possible, and what makes the number under the thumb the same
    // number as the one on the meter.
    test('gives back the decibels the visualizer was given', () {
      for (final db in [-90.0, -80.0, -70.0, -55.0, -45.0, -35.0, -30.0]) {
        expect(
          MicTap.decibelsOf(bandAt(db)),
          closeTo(db, 1e-9),
          reason: '$db dB',
        );
      }
    });

    test('silence reads the bottom of the scale', () {
      expect(MicTap.decibelsOf(bandAt(-100)), MicTap.silenceDb);
      expect(MicTap.decibelsOf(0), MicTap.silenceDb);
    });

    // The visualizer clamps its own input at -30 dB, so everything louder is
    // reported as -30. The slider stops there for that reason, not by choice.
    test('anything above the ceiling reads as the ceiling', () {
      expect(MicTap.decibelsOf(bandAt(-30)), MicTap.ceilingDb);
      expect(MicTap.decibelsOf(bandAt(-10)), MicTap.ceilingDb);
      expect(MicTap.decibelsOf(bandAt(0)), MicTap.ceilingDb);
    });

    test('nonsense from the channel stays inside the scale', () {
      for (final band in [-1.0, 0.0, 0.5, 1.0, 2.0, 1e6]) {
        expect(
          MicTap.decibelsOf(band),
          inInclusiveRange(MicTap.silenceDb, MicTap.ceilingDb),
          reason: 'band $band',
        );
      }
    });

    test('the test inverse agrees with the reconstruction', () {
      for (final db in [-80.0, -65.0, -50.0, -30.0]) {
        expect(
          MicTap.decibelsOf(MicTap.bandForDecibels(db)),
          closeTo(db, 1e-9),
          reason: '$db dB',
        );
      }
    });
  });

  group('before anything has been measured', () {
    test('a fresh tap is not live and reads silence', () {
      final tap = MicTap();

      expect(tap.isLive, isFalse);
      expect(tap.takePeakDb(), MicTap.silenceDb);
    });

    // `isLive` is what stops the gate acting on a measurement that is not
    // arriving — an older plugin, a platform without the native visualizer.
    // Treating "no tap" as "a silent room" would gate the microphone shut and
    // leave somebody inaudible.
    test('never delivering is not the same as reading silence', () {
      final tap = MicTap();

      expect(tap.takePeakDb(), MicTap.silenceDb);
      expect(tap.isLive, isFalse, reason: 'still nothing, not a reading');
    });
  });
}
