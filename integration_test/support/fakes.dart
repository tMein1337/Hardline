// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/live_participant.dart';
import 'package:hardline/features/voice/livekit_call_controller.dart';
import 'package:hardline/features/voice/noise_gate.dart';
import 'package:hardline/features/voice/speaking_participants.dart';

import 'win32.dart';

/// A call that exists only as far as the rest of the app can tell.
///
/// The real controller wants a Matrix client, a token service and a live SFU,
/// none of which an integration test may have. What the overlay and the chords
/// read off it is small — whether a call is up, who is in it, and the two
/// switches — so this holds exactly that and lets a test set it.
class FakeCallController extends ChangeNotifier
    implements LiveKitCallController {
  @override
  bool isInCall = false;

  @override
  bool micMuted = false;

  @override
  bool deafened = false;

  @override
  List<LiveParticipant> participants = const [];

  @override
  final ValueNotifier<SpeakingParticipants> speaking = ValueNotifier(
    const SpeakingParticipants.silent(),
  );

  @override
  final ValueNotifier<MicLevel> micLevel = ValueNotifier(const MicLevel.none());

  int sharesStopped = 0;

  /// Puts a call up with [people] in it, or takes it down with none.
  void setCall(List<LiveParticipant> people) {
    isInCall = people.isNotEmpty;
    participants = people;
    notifyListeners();
  }

  @override
  Future<void> setMicMuted(bool muted, {bool persist = true}) async {
    micMuted = muted;
    notifyListeners();
  }

  @override
  Future<void> setDeafened(bool deafened) async {
    this.deafened = deafened;
    notifyListeners();
  }

  @override
  Future<void> stopAllScreenShares() async => sharesStopped++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Somebody in the call, with no avatar to fetch.
LiveParticipant person(String userId, {String? name}) => LiveParticipant(
  userId: userId,
  identity: userId,
  deviceId: 'DEVICE',
  displayName: name ?? userId,
  avatarMxc: null,
  isLocal: false,
  micMuted: false,
  feeds: const [],
);

/// Refuses to run a suite on a desktop somebody is using.
///
/// These suites press real chords, drag the real mouse and put a topmost
/// window over the monitor. If another application has the foreground — a
/// game, most likely, since that is what the overlay is for — those keys go
/// to it and that window goes over it. Found the obvious way: a run started
/// while a match was in progress.
///
/// Called at the top of each suite's `main`, so every test in it fails at
/// once with the reason rather than one at a time with a timeout.
void requireOwnDesktop() {
  setUpAll(() {
    if (!foregroundIsOurs) {
      fail(
        'Another application has the foreground, so this suite will not '
        'run: it would send key presses to it and draw over it. Run it when '
        'the machine is otherwise idle, and leave the test window in front.',
      );
    }
  });
}

/// Pumps until [condition] holds, or fails the test saying what was awaited.
///
/// `pumpAndSettle` waits for frames to stop being scheduled, which says
/// nothing about a reply still on its way back from the runner. Everything
/// these tests assert about Windows arrives that way.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after ${timeout.inSeconds}s waiting for: $reason');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
