// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../call_controller_provider.dart';
import '../mic_tap.dart';
import '../noise_gate.dart';
import '../voice_prefs_state.dart';

/// A live microphone level, with the breakpoint drawn across it.
///
/// The threshold is a number nobody can pick in the abstract. What counts as
/// "above the noise" depends on the microphone, its gain, the room and how far
/// away the person sits — so the only way to set it is to watch your own level
/// while you talk and put the line between the two. That is what this is for,
/// and it is why the setting lives next to it rather than on its own.
///
/// Shows nothing but an explanation when there is no call: the level comes from
/// the published microphone track, and outside a call there is no track.
class MicLevelMeter extends ConsumerStatefulWidget {
  const MicLevelMeter({super.key, required this.thresholdDb});

  /// Where the breakpoint sits, in dB.
  final double thresholdDb;

  @override
  ConsumerState<MicLevelMeter> createState() => _MicLevelMeterState();
}

class _MicLevelMeterState extends ConsumerState<MicLevelMeter> {
  ValueListenable<MicLevel>? _source;
  MicLevel _level = const MicLevel.none();

  /// The peak, decayed slowly.
  ///
  /// Speech is spiky, and a bar that follows the instantaneous level exactly is
  /// a flicker rather than a reading. Holding the peak and letting it fall is
  /// what every level meter does, for the same reason: the eye needs something
  /// to compare against the breakpoint.
  double _peak = MicTap.silenceDb;

  /// Drives the fall.
  ///
  /// The decay used to happen inside the level listener, which was wrong twice
  /// over. A `ValueNotifier` only fires when its value *changes*, so a level
  /// sitting still — silence, most obviously — stopped the decay dead and left
  /// the bar frozen wherever it happened to be. And an exponential fall towards
  /// the floor never arrives, so the last sliver of green stayed lit under a
  /// reading of -100 dB. A meter has to fall on its own clock.
  Timer? _fall;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = ref.watch(micLevelProvider);
    if (identical(_source, source)) return;
    _source?.removeListener(_read);
    _source = source..addListener(_read);
    _level = source.value;
  }

  @override
  void initState() {
    super.initState();
    _fall = Timer.periodic(const Duration(milliseconds: 60), (_) => _decay());
  }

  @override
  void dispose() {
    _fall?.cancel();
    _source?.removeListener(_read);
    super.dispose();
  }

  void _decay() {
    if (_peak <= MicTap.silenceDb) return;

    // Snapped rather than approached. Exponential decay is asymptotic, so
    // without this the bar keeps a hair of width for ever, contradicting the
    // -100 dB printed underneath it.
    final next = _peak - (_peak - MicTap.silenceDb) * 0.25;
    setState(
      () => _peak = next - MicTap.silenceDb < 0.5 ? MicTap.silenceDb : next,
    );
  }

  void _read() {
    final next = _source?.value ?? const MicLevel.none();
    if (!mounted) return;
    setState(() {
      _level = next;
      // Only ever raised here. The fall is the timer's job, so that it keeps
      // happening when the level stops changing.
      if (next.db > _peak) _peak = next.db;
      if (!next.measured) _peak = MicTap.silenceDb;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // The bar spans exactly what the slider can select, so the breakpoint
    // being dragged is the mark shown against the voice.
    double position(double db) =>
        ((db - kMinThresholdDb) / (kMaxThresholdDb - kMinThresholdDb)).clamp(
          0.0,
          1.0,
        );

    final over = _level.measured && _level.db >= widget.thresholdDb;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 14,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.inputBackground,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const SizedBox.expand(),
                  ),
                  FractionallySizedBox(
                    widthFactor: _level.measured ? position(_peak) : 0.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // Amber below the breakpoint, green above. The palette's
                        // annunciator language reads amber as caution and
                        // green as normal, and the normal state of a meter is
                        // the one where your voice is getting through — so
                        // green is what being heard looks like, and the
                        // colour that draws the eye is the one saying you are
                        // not.
                        color: over
                            ? colors.voiceConnected
                            : colors.voiceSpeakingRing,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Positioned(
                    left: (width * position(widget.thresholdDb)).clamp(
                      0.0,
                      width - 2,
                    ),
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: ColoredBox(color: colors.textPrimary),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(_caption(), style: context.text.timestamp),
      ],
    );
  }

  String _caption() {
    if (!_level.measured) {
      return 'Join a call to see your microphone level. The breakpoint is where '
          'you start counting as speaking.';
    }

    final now = '${_level.db.round()} dB';
    if (!_level.gateAvailable) {
      return '$now — this build cannot gate the microphone, so the breakpoint '
          'only decides when you are shown as speaking.';
    }
    if (!_level.gateActive) {
      return _level.db < widget.thresholdDb
          ? '$now — below the breakpoint. Still being sent; you are just not '
                'shown as speaking.'
          : '$now — above the breakpoint.';
    }
    return _level.gateOpen
        ? '$now — sending.'
        : '$now — silent. Nothing below the breakpoint is being sent.';
  }
}
