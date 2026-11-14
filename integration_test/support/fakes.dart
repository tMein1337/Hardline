// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/live_participant.dart';
import 'package:hardline/features/voice/livekit_call_controller.dart';
import 'package:hardline/features/voice/noise_gate.dart';
import 'package:hardline/features/voice/speaking_participants.dart';

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
