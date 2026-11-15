// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:hardline/features/voice/audio_device_wake.dart';
import 'package:hardline/features/voice/call_controller_provider.dart';
import 'package:hardline/features/voice/livekit_call_controller.dart';
import 'package:hardline/features/voice/livekit_token_service.dart';
import 'package:hardline/features/voice/mic_tap.dart';
import 'package:hardline/features/voice/voice_prefs_controller.dart';
import 'package:hardline/features/voice/voice_prefs_state.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'support/audio.dart';
import 'support/fakes.dart';
import 'support/live.dart';

// What the other side of a call hears, measured rather than listened to.
//
// The noise gate's checks were written for two people: somebody talks,
// somebody else says whether they heard the start of the sentence, or holes
// in it, or nothing.
// Here the person talking is a signal the test writes into a virtual audio
// cable, and the person listening is a second call participant reading its
// own receiver statistics twenty times a second.
//
//  * **A is the app**, signed in through its login form, with "CABLE Output"
//    chosen as its microphone in its own voice settings.
//  * **B is a second `LiveKitCallController`** — the app's own call code,
//    not a stand-in — signed in as the second account, with A's audio
//    arriving at it the way it would arrive at anybody. Not muted: the two
//    share the process's one audio device, and B muting stopped the capture
//    A was talking through.
//
// That sharing hides one case, so it is tested before B exists: A alone,
// where nothing but A's own sender keeps the microphone being read. See
// `CaptureKeeper`.
//
// WebRTC's noise suppression is switched off for both (see
// `debugMicAudioProcessing`): it takes a synthetic voice for noise.
//
// Both play out on the digital output, which has nothing plugged into it, so
// none of this is audible on the machine running it.
//
// Needs the live accounts (see `support/live.dart`) and VB-Audio's virtual
// cable. Without either, it is skipped or says which is missing.

const _cableIn = 'CABLE Input';
const _cableOut = 'CABLE Output';
const _quietOut = 'Realtek Digital Output';

/// What B hears of A, sample by sample.
class _Ear {
  _Ear(this.track);

  final lk.RemoteAudioTrack track;

  /// Mean square level in each interval since [listen] began, keyed by when
  /// the interval ended. Zero is true silence: nothing was decoded.
  final bins = <(Duration, double)>[];

  /// When each new RTP packet was first seen, as far as twenty-millisecond
  /// polling can tell.
  ///
  /// The level cannot show a short gap: when packets stop, the receiver
  /// conceals the loss with a decaying copy of what it last had, and that
  /// has energy. Packets are what the gate actually withholds.
  final arrivals = <Duration>[];

  final buffer = <(Duration, double)>[];
  String bufferTimeline() => [
    for (var i = 0; i < buffer.length; i += 10)
      '${buffer[i].$1.inMilliseconds}:${buffer[i].$2.round()}',
  ].join(' ');

  /// Listens for [duration], from the moment this is called.
  Future<void> listen(Duration duration) async {
    bins.clear();
    arrivals.clear();
    final clock = Stopwatch()..start();
    double? energy;
    double? samples;
    num? packets;
    buffer.clear();
    double? jbD;
    double? jbN;
    while (clock.elapsed < duration) {
      final stats = await track.getReceiverStats();
      final e = stats?.totalAudioEnergy?.toDouble();
      final s = stats?.totalSamplesDuration?.toDouble();
      if (e != null && s != null) {
        if (energy != null && samples != null && s > samples) {
          bins.add((clock.elapsed, (e - energy) / (s - samples)));
        }
        energy = e;
        samples = s;
      }
      final p = stats?.packetsReceived;
      if (p != null) {
        if (packets != null && p > packets) arrivals.add(clock.elapsed);
        packets = p;
      }
      // Not in LiveKit's parsed statistics, so read off the raw report.
      final raw = await track.receiver?.getStats();
      for (final r in raw ?? const <rtc.StatsReport>[]) {
        if (r.type != 'inbound-rtp') continue;
        final d = (r.values['jitterBufferDelay'] as num?)?.toDouble();
        final n = (r.values['jitterBufferEmittedCount'] as num?)?.toDouble();
        if (d != null && n != null) {
          if (jbD != null && jbN != null && n > jbN) {
            buffer.add((clock.elapsed, 1000 * (d - jbD) / (n - jbN)));
          }
          jbD = d;
          jbN = n;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// The longest stretch inside [from, to) with no packet arriving.
  Duration longestGap(Duration from, Duration to) {
    var longest = Duration.zero;
    var last = from;
    for (final at in arrivals) {
      if (at < from) continue;
      if (at >= to) break;
      if (at - last > longest) longest = at - last;
      last = at;
    }
    if (to - last > longest) longest = to - last;
    return longest;
  }

  /// Level in dB of the loudest bin, or -inf for nothing at all.
  double peakDb() => _db(bins.map((b) => b.$2).fold(0.0, math.max));

  /// Level in dB over [from, to).
  double dbBetween(Duration from, Duration to) {
    final inside = [
      for (final (at, level) in bins)
        if (at >= from && at < to) level,
    ];
    if (inside.isEmpty) return double.negativeInfinity;
    return _db(inside.reduce((a, b) => a + b) / inside.length);
  }

  /// When the level first reached [db], or null if it never did.
  Duration? firstAbove(double db, {Duration after = Duration.zero}) {
    for (final (at, level) in bins) {
      if (at >= after && _db(level) >= db) return at;
    }
    return null;
  }

  /// The whole listen as one character per 100ms: `X` loud, `m` quiet but
  /// there, `.` no packet arrived.
  String timeline(double loudDb) {
    final out = StringBuffer();
    for (var slot = 0; ; slot++) {
      final from = Duration(milliseconds: slot * 100);
      if (bins.isEmpty || from > bins.last.$1) break;
      final inside = [
        for (final (at, level) in bins)
          if (at >= from && at < from + const Duration(milliseconds: 100))
            level,
      ];
      final arrived = arrivals.any(
        (at) => at >= from && at < from + const Duration(milliseconds: 100),
      );
      if (!arrived) {
        out.write('.');
      } else if (inside.any((level) => _db(level) >= loudDb)) {
        out.write('X');
      } else {
        out.write('m');
      }
    }
    return out.toString();
  }

  static double _db(double meanSquare) => meanSquare <= 0
      ? double.negativeInfinity
      : 10 * math.log(meanSquare) / math.ln10;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (liveSkip == null) requireOwnDesktop();

  late LiveSession live;
  late AudioOut cable;
  late LiveKitCallController a;
  late LiveKitCallController b;
  late VoicePrefsController aPrefs;

  /// Joins both to a call in a fresh room and returns B's ear on A.
  Future<_Ear> call(WidgetTester tester, {required bool encrypted}) async {
    live = await LiveSession.start(tester);
    addTearDown(live.close);

    final opened = AudioOut.open(_cableIn);
    expect(
      opened,
      isNotNull,
      reason:
          'No "$_cableIn" output. This suite plays its voice into VB-Audio\'s '
          'virtual cable; outputs here: ${outputDevices()}',
    );
    cable = opened!;
    addTearDown(cable.close);

    // Through the app's own helper, outside any call — which is exactly
    // where the native module used to list nothing at all.
    final (:inputs, :outputs) = await listAudioDevices();
    expect(
      inputs,
      isNotEmpty,
      reason: 'outside a call the voice settings must still list devices',
    );
    final mic = inputs.firstWhere(
      (d) => d.label.contains(_cableOut),
      orElse: () => throw StateError('no "$_cableOut" input in $inputs'),
    );
    final speaker = outputs.firstWhere(
      (d) => d.label.contains(_quietOut),
      orElse: () => throw StateError('no "$_quietOut" output in $outputs'),
    );
    final micRef = AudioDeviceRef(deviceId: mic.deviceId, label: mic.label);
    final speakerRef = AudioDeviceRef(
      deviceId: speaker.deviceId,
      label: speaker.label,
    );

    // A's settings, set the way the voice pane sets them.
    aPrefs = live.container.read(voicePrefsProvider.notifier);
    await aPrefs.setInputDevice(micRef);
    await aPrefs.setOutputDevice(speakerRef);
    // See debugMicAudioProcessing: the suppressor would take the test's
    // synthetic voice for noise. Applies to B too, which is the same class.
    debugMicAudioProcessing = false;
    addTearDown(() => debugMicAudioProcessing = true);
    await aPrefs.setNoiseGate(false);
    await aPrefs.setMicGainDb(0);
    await aPrefs.setSelfMuted(false);

    final roomId = await live.roomWithBoth(encrypted: encrypted);

    a = live.container.read(callControllerProvider);
    await a.join(roomId);
    await pumpUntil(
      tester,
      () => a.isInCall,
      reason: 'A to be in the call (${a.error ?? a.status})',
      timeout: const Duration(seconds: 60),
    );

    // Before B exists: A alone in the process, with the gate on. This is the
    // case a real user is in, and the one the rest of this suite cannot see —
    // once B's controller is up, its sender keeps the audio device recording
    // for both of them. Alone, closing the gate used to stop the recording,
    // which blinded the tap, which meant the gate never opened again.
    // The breakpoint just above the room, as the settings say to set it. The
    // room here is the cable's own floor: with noise suppression off it is
    // not digital silence but a faint hiss, measured at -81 with peaks of
    // -79 — over the default breakpoint, which would rightly hold the gate
    // open on it.
    var room = MicTap.silenceDb;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      room = math.max(room, a.micLevel.value.db);
    }
    final soloBreakpoint = (room + 10).clamp(kMinThresholdDb, kMaxThresholdDb);
    debugPrint('[call] A alone: the quiet cable reads $room dB');
    await aPrefs.setMicThresholdDb(soloBreakpoint);
    await aPrefs.setNoiseGate(true);
    await pumpUntil(
      tester,
      () => a.micLevel.value.gateActive && !a.micLevel.value.gateOpen,
      reason: 'A\'s gate to close on the silent cable',
      timeout: const Duration(seconds: 10),
    );
    // Shut for a while, as it would be between two remarks.
    final quietReadings = <String>[];
    final quietWatch = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final m = a.micLevel.value;
      quietReadings.add('${m.db.round()}${m.gateOpen ? 'O' : '_'}');
    });
    await tester.pump(const Duration(seconds: 2));
    quietWatch.cancel();
    expect(
      a.micLevel.value.gateOpen,
      isFalse,
      reason:
          'nothing is playing into the cable, so the gate should stay shut; '
          'A read (dB, gate): ${quietReadings.join(' ')}',
    );
    var reopened = false;
    var played = false;
    final words = Signal();
    for (var i = 0; i < 4; i++) {
      words
        ..voice(const Duration(milliseconds: 400), dbfs: -14)
        ..silence(const Duration(milliseconds: 200));
    }
    unawaited(cable.play(words.build()).whenComplete(() => played = true));
    var alone = double.negativeInfinity;
    while (!played) {
      final m = a.micLevel.value;
      alone = math.max(alone, m.db);
      if (m.gateOpen && m.db >= soloBreakpoint) reopened = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    debugPrint('[call] A alone, gate closed, then spoke: reads $alone dB');
    expect(
      reopened,
      isTrue,
      reason:
          'alone in the process, A\'s gate must reopen when A speaks — the '
          'tap must still be hearing the microphone while the gate is shut',
    );
    await aPrefs.setNoiseGate(false);

    b = LiveKitCallController(
      client: live.b,
      tokenService: LiveKitTokenService(client: live.b),
      readPrefs: () => VoicePrefsState(
        selfMuted: false,
        inputDevice: micRef,
        outputDevice: speakerRef,
      ),
    );
    addTearDown(() async {
      await b.leave();
      b.dispose();
      await a.leave();
    });
    await b.join(roomId);
    await pumpUntil(
      tester,
      () => b.isInCall,
      reason: 'B to be in the call (${b.error ?? b.status})',
      timeout: const Duration(seconds: 60),
    );

    lk.RemoteAudioTrack? track() {
      for (final participant
          in b.liveKitRoom?.remoteParticipants.values ??
              const <lk.RemoteParticipant>[]) {
        if (!participant.identity.startsWith(live.aId)) continue;
        for (final publication in participant.audioTrackPublications) {
          if (publication.track case final lk.RemoteAudioTrack audio) {
            return audio;
          }
        }
      }
      return null;
    }

    await pumpUntil(
      tester,
      () => track() != null,
      reason: 'B to be subscribed to A\'s microphone',
      timeout: const Duration(seconds: 60),
    );
    // A moment for both ends' audio paths to settle before anything is
    // measured — the first second of a track is full of start-up concealment.
    await tester.pump(const Duration(seconds: 2));
    return _Ear(track()!);
  }

  /// Plays [signal] into A's microphone while B listens to all of it, plus
  /// [tail] for what is still in flight.
  Future<void> say(
    _Ear ear,
    Signal signal, {
    Duration tail = const Duration(milliseconds: 800),
  }) async {
    await Future.wait([
      cable.play(signal.build()),
      ear.listen(signal.length + tail),
    ]);
  }

  /// The loudest A's own meter read while [signal] played.
  Future<double> meter(Signal signal) async {
    var loudest = double.negativeInfinity;
    final playing = cable.play(signal.build());
    var done = false;
    unawaited(playing.whenComplete(() => done = true));
    while (!done) {
      loudest = math.max(loudest, a.micLevel.value.db);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return loudest;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 1200));

  testWidgets('the noise gate, heard from the other end', (tester) async {
    final ear = await call(tester, encrypted: false);

    // ---------------------------------------------------------------------
    // Calibration: where a voice and a murmur land on A's own meter.
    // ---------------------------------------------------------------------
    const loud = -14.0;
    const murmur = -52.0;
    // Words with gaps rather than one long tone. WebRTC's noise suppression
    // runs before the tap, and a steady synthetic voice is exactly what it
    // learns as noise: held for two seconds, it was pulled down until A's
    // meter barely told it from the murmur. Real speech never holds still
    // long enough for that, and neither does this.
    Signal words(double dbfs) {
      final signal = Signal();
      for (var i = 0; i < 4; i++) {
        signal
          ..voice(const Duration(milliseconds: 400), dbfs: dbfs)
          ..silence(const Duration(milliseconds: 200));
      }
      return signal;
    }

    final loudDb = await meter(words(loud));
    await settle();
    final murmurDb = await meter(
      Signal().voice(const Duration(seconds: 2), dbfs: murmur),
    );
    debugPrint(
      '[call] A\'s meter: voice at ${loudDb.toStringAsFixed(1)} dB, murmur '
      'at ${murmurDb.toStringAsFixed(1)} dB',
    );
    // Just above the room noise, as the settings say to set it — not halfway
    // to the voice, which puts every quieter syllable below the line.
    final breakpoint = (murmurDb + 6).clamp(kMinThresholdDb, kMaxThresholdDb);
    expect(
      loudDb,
      greaterThan(breakpoint + 3),
      reason: 'the voice has to clear a breakpoint set just above the murmur',
    );

    // Ungated, the murmur reaches B — otherwise silence with the gate on
    // would prove nothing.
    await settle();
    await say(ear, Signal().voice(const Duration(seconds: 2), dbfs: murmur));
    final murmurHeard = ear.dbBetween(
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 2000),
    );
    debugPrint('[call] B hears the ungated murmur at $murmurHeard dB');
    expect(murmurHeard, greaterThan(double.negativeInfinity));

    // Ungated onset: how long after the first sample B hears a voice. This
    // is the network and both audio paths; what the gate adds is measured
    // against it.
    await settle();
    await say(
      ear,
      Signal()
        ..silence(const Duration(seconds: 1))
        ..voice(const Duration(milliseconds: 1500), dbfs: loud),
    );
    final threshold = ear.peakDb() - 15;
    final ungatedOnset = ear.firstAbove(threshold)!;

    // ---------------------------------------------------------------------
    // 4.1 — the gate gates, and does not eat the first syllable.
    // ---------------------------------------------------------------------
    await aPrefs.setMicThresholdDb(breakpoint);
    await aPrefs.setNoiseGate(true);
    await settle();
    await say(
      ear,
      Signal()
        ..voice(const Duration(seconds: 3), dbfs: murmur)
        ..voice(const Duration(milliseconds: 1500), dbfs: loud),
    );
    final murmurGated = ear.dbBetween(
      const Duration(milliseconds: 800),
      const Duration(milliseconds: 3000),
    );
    final gatedOnset = ear.firstAbove(
      threshold,
      after: const Duration(milliseconds: 2500),
    );
    debugPrint(
      '[call] gate on: murmur at B $murmurGated dB; voice heard '
      '${gatedOnset == null ? "never" : "${(gatedOnset - const Duration(seconds: 3)).inMilliseconds}ms"} '
      'after it began, against ${(ungatedOnset - const Duration(seconds: 1)).inMilliseconds}ms ungated',
    );
    expect(
      murmurGated,
      double.negativeInfinity,
      reason: 'below the breakpoint, B must receive nothing at all',
    );
    expect(gatedOnset, isNotNull, reason: 'above it, B must hear the voice');
    final clipped =
        (gatedOnset! - const Duration(seconds: 3)) -
        (ungatedOnset - const Duration(seconds: 1));
    debugPrint('[call] the gate costs the onset ${clipped.inMilliseconds}ms');
    expect(
      clipped,
      lessThan(const Duration(milliseconds: 200)),
      reason:
          'a gate that opens later than this loses the first syllable of a '
          'word, which is what 4.1 warns about',
    );

    // ---------------------------------------------------------------------
    // 4.2 — no holes inside a sentence; and the gate does close in a long
    // pause, so the first half is not passing by doing nothing.
    // ---------------------------------------------------------------------
    await settle();
    final sentence = Signal();
    for (var word = 0; word < 6; word++) {
      sentence
        ..voice(const Duration(milliseconds: 450), dbfs: loud)
        ..voice(const Duration(milliseconds: 250), dbfs: murmur);
    }
    sentence
      ..voice(const Duration(milliseconds: 1600), dbfs: murmur)
      ..voice(const Duration(milliseconds: 600), dbfs: loud);
    final gateTimeline = StringBuffer();
    final sampling = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final m = a.micLevel.value;
      gateTimeline.write(m.gateOpen ? (m.db >= breakpoint ? 'O' : 'o') : '_');
    });
    await say(ear, sentence);
    sampling.cancel();
    debugPrint('[call] A gate  (100ms): $gateTimeline');
    debugPrint('[call] B hears (100ms): ${ear.timeline(threshold)}');
    debugPrint('[call] B jitter buffer (elapsed:ms): ${ear.bufferTimeline()}');
    // Everything at B arrives this much later than it was played.
    final latency = ungatedOnset - const Duration(seconds: 1);
    const speechEnds = Duration(milliseconds: 700 * 6);
    final hole = ear.longestGap(
      latency + const Duration(milliseconds: 200),
      latency + speechEnds,
    );
    final pause = ear.longestGap(
      latency + speechEnds + const Duration(milliseconds: 500),
      latency + speechEnds + const Duration(milliseconds: 1500),
    );
    debugPrint(
      '[call] longest gap in packets inside the sentence '
      '${hole.inMilliseconds}ms; in the long pause ${pause.inMilliseconds}ms',
    );
    final firstOpen = gateTimeline.toString().indexOf('O');
    expect(
      gateTimeline.toString().substring(
        firstOpen,
        speechEnds.inMilliseconds ~/ 100,
      ),
      isNot(contains('_')),
      reason:
          'A\'s gate must stay open through pauses shorter than its hold; '
          'a closing between words is a sentence that reaches the listener '
          'in pieces',
    );
    // A sanity bound, not the test of 4.2 — that is A's own timeline above,
    // which sees a closing directly. Packets cross the internet to the SFU
    // and back, and gaps of 150ms were seen with the gate wide open.
    expect(
      hole,
      lessThan(const Duration(milliseconds: 300)),
      reason: 'and B must receive packets right through the sentence',
    );
    expect(
      pause,
      greaterThan(const Duration(milliseconds: 400)),
      reason: 'a pause longer than the hold should close the gate',
    );
    // ---------------------------------------------------------------------
    // 4.3 — the breakpoint above the voice: nothing, and the meter says why.
    // ---------------------------------------------------------------------
    // The highest the setting goes, which is far above any voice here.
    const tooHigh = kMaxThresholdDb;
    await aPrefs.setMicThresholdDb(tooHigh);
    await settle();
    final level = <double>[];
    final reading = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => level.add(a.micLevel.value.db),
    );
    final gateStates = <bool>[];
    final watching = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => gateStates.add(a.micLevel.value.gateOpen),
    );
    await say(ear, Signal().voice(const Duration(seconds: 3), dbfs: loud));
    reading.cancel();
    watching.cancel();
    debugPrint(
      '[call] breakpoint at $tooHigh dB: B peak ${ear.peakDb()} dB, A\'s '
      'meter peaked at ${level.fold(double.negativeInfinity, math.max)} dB, '
      'gate open in ${gateStates.where((open) => open).length} of '
      '${gateStates.length} readings, ${ear.arrivals.length} packets arrived',
    );
    // Packets, not level. With nothing arriving, B's receiver still plays out
    // a decaying trace of whatever it last had — measured between -90 and
    // -76 dB, far below hearing — so the level is never exactly nothing.
    // What the gate withholds is packets.
    expect(
      ear.arrivals,
      isEmpty,
      reason: 'set above the voice, B must receive nothing at all',
    );
    expect(
      level.fold(double.negativeInfinity, math.max),
      lessThan(tooHigh),
      reason: 'and A\'s own meter must show the level below the breakpoint',
    );
    expect(gateStates.where((open) => open), isEmpty);

    // ---------------------------------------------------------------------
    // 4.5 — switching the gate off brings A back at once, without rejoining.
    // ---------------------------------------------------------------------
    final restored = Signal().voice(const Duration(seconds: 4), dbfs: loud);
    final switchOff = Timer(
      const Duration(milliseconds: 1500),
      () => unawaited(aPrefs.setNoiseGate(false)),
    );
    await say(ear, restored);
    switchOff.cancel();
    final back = ear.firstAbove(threshold);
    final ungated = ungatedOnset - const Duration(seconds: 1);
    debugPrint(
      '[call] gate switched off at 1500ms; B hears A from '
      '${back?.inMilliseconds}ms, against ${ungated.inMilliseconds}ms '
      'ungated; B jitter buffer (elapsed:ms): ${ear.bufferTimeline()}',
    );
    expect(back, isNotNull, reason: 'B must hear A again');
    // Not "within the ungated latency", which is what was asked for and which
    // this rig cannot judge: B's jitter buffer grows by about 100ms for every
    // second of audio, gate or no gate — it was seen climbing past a second
    // while A's gate never closed — so anything measured late in this test
    // carries a delay that has nothing to do with A. See TODOs.md item 2.
    expect(
      back! - const Duration(milliseconds: 1500),
      lessThan(const Duration(seconds: 2)),
      reason: 'B must hear A again soon after the switch',
    );
    expect(a.isInCall, isTrue);

    // ---------------------------------------------------------------------
    // The ring, from the other end: B's speaking set follows A's voice.
    // ---------------------------------------------------------------------
    await settle();
    var heardSpeaking = false;
    void onSpeaking() {
      if (b.speaking.value.userIds.contains(live.aId)) heardSpeaking = true;
    }

    b.speaking.addListener(onSpeaking);
    await say(ear, Signal().voice(const Duration(seconds: 2), dbfs: loud));
    b.speaking.removeListener(onSpeaking);
    expect(heardSpeaking, isTrue, reason: 'B should see A speaking');

    // Waited for rather than checked after a fixed pause: the ring goes out
    // when A's audio stops *at B*, and B's jitter buffer — most of a second by
    // now, see 4.5 — moves that well past the moment A went quiet.
    final quiet = Stopwatch()..start();
    await pumpUntil(
      tester,
      () => !b.speaking.value.userIds.contains(live.aId),
      reason: 'B to stop seeing A speaking once A is quiet',
      timeout: const Duration(seconds: 5),
    );
    debugPrint(
      '[call] B\'s ring for A went out ${quiet.elapsedMilliseconds}ms after '
      'the listen ended',
    );
  }, skip: liveSkip != null);

  // 4.4: the gate works by switching the sender's encoding off, in a call
  // whose frames are encrypted by a cryptor attached to that same sender.
  testWidgets('an encrypted call survives the gate being toggled', (
    tester,
  ) async {
    final ear = await call(tester, encrypted: true);
    expect(live.encryption, isTrue, reason: 'vodozemac did not load');

    const loud = -14.0;
    await say(ear, Signal().voice(const Duration(seconds: 2), dbfs: loud));
    final before = ear.dbBetween(
      const Duration(milliseconds: 600),
      const Duration(milliseconds: 2000),
    );
    debugPrint('[call] encrypted: B hears A at $before dB');
    expect(
      before,
      greaterThan(double.negativeInfinity),
      reason: 'B must be able to decrypt A at all',
    );

    // Closed and open, ten times, with a voice going the whole while.
    await aPrefs.setMicThresholdDb(kMaxThresholdDb);
    final toggling = () async {
      for (var i = 0; i < 10; i++) {
        await aPrefs.setNoiseGate(true);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await aPrefs.setNoiseGate(false);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }();
    await say(ear, Signal().voice(const Duration(seconds: 8), dbfs: loud));
    await toggling;

    await settle();
    await say(ear, Signal().voice(const Duration(seconds: 2), dbfs: loud));
    final after = ear.dbBetween(
      const Duration(milliseconds: 600),
      const Duration(milliseconds: 2000),
    );
    debugPrint('[call] encrypted, after toggling: B hears A at $after dB');
    expect(
      after,
      greaterThan(before - 6),
      reason:
          'after ten closings and openings B must still decode A at the '
          'level it did before; garbled or lost frames read far lower',
    );
  }, skip: liveSkip != null);
}
