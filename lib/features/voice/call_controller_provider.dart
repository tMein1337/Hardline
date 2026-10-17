// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// `AppExitResponse` is a dart:ui type; `show` keeps the rest of dart:ui from
// colliding with the widgets library imported below.
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import 'call_logging.dart';
import 'livekit_call_controller.dart';
import 'livekit_token_service.dart';
import 'noise_gate.dart';
import 'speaking_participants.dart';
import 'voice_prefs_controller.dart';

/// Exchanges Matrix OpenID tokens for LiveKit JWTs. Stateless apart from its
/// HTTP client, so one for the app is plenty.
final liveKitTokenServiceProvider = Provider<LiveKitTokenService>((ref) {
  final service = LiveKitTokenService(client: ref.watch(clientProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// The app's single call controller.
///
/// Not auto-disposed, unlike `timelineControllerProvider`: a call has to survive
/// the user switching rooms and spaces, which is exactly what auto-dispose would
/// tear down. There is one call at a time, so one controller is right.
///
/// Body is synchronous so `ref.onDispose` is registered before anything awaits —
/// the discipline `timeline_provider.dart` documents.
final callControllerProvider = Provider<LiveKitCallController>((ref) {
  final controller = LiveKitCallController(
    client: ref.watch(clientProvider),
    tokenService: ref.watch(liveKitTokenServiceProvider),
    // `read`, not `watch`: the controller pulls the current settings when it
    // needs them. Watching would rebuild the controller — and so drop the live
    // call — every time a volume slider moved.
    readPrefs: () => ref.read(voicePrefsProvider),
  );
  // Persist hooks. The controller owns the live mute/deafen state; storage is
  // the provider's business, which keeps the controller free of Riverpod.
  final prefs = ref.read(voicePrefsProvider.notifier);
  controller.onSelfMuteChanged = (muted) => prefs.setSelfMuted(muted);
  controller.onDeafenChanged = (deafened) => prefs.setDeafened(deafened);

  // Applied from here rather than from the settings pane, so it is in force
  // from launch instead of from whenever somebody last opened that screen —
  // which for a diagnostic is the wrong way round, since the launch is often
  // the part worth seeing.
  setVerboseCallLogging(ref.read(voicePrefsProvider).verboseCallLog);

  // A slider drag has to be audible immediately, so any preference change
  // re-applies to the live tracks. `listen`, not `watch`: watching would
  // rebuild the controller and drop the call on every volume tweak.
  ref.listen(voicePrefsProvider, (_, next) {
    controller.onPrefsChanged();
    setVerboseCallLogging(next.verboseCallLog);
  });

  // Leave the call before the window closes.
  //
  // Without this, quitting mid-call leaves our `m.call.member` state event
  // published: everyone else keeps seeing us in the channel until the
  // membership expires, which is hours. The controller's own `dispose` is not
  // enough — it fires as the isolate is being torn down, far too late for the
  // HTTP request that withdraws the state event to complete.
  //
  // This works because the Windows runner forwards messages through
  // `HandleTopLevelWindowProc`, which is where the embedder turns WM_CLOSE into
  // an exit request the framework can answer.
  final lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      // Bounded: a hung network must never leave someone unable to close their
      // own application. A few seconds is ample for one state event, and the
      // membership expires on its own if we lose the race.
      await controller.leave().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      return AppExitResponse.exit;
    },
  );

  ref.onDispose(lifecycle.dispose);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Who is audible right now.
///
/// A provider of its own rather than reaching through `callControllerProvider`,
/// so the widgets that draw a speaking ring depend on exactly this and a test
/// can hand them a notifier without building a controller — which would want a
/// Matrix client, a token service and a live SFU.
final speakingParticipantsProvider =
    Provider<ValueListenable<SpeakingParticipants>>(
      (ref) => ref.watch(callControllerProvider).speaking,
    );

/// What the microphone is picking up, for the meter in the settings pane.
///
/// Separate from [speakingParticipantsProvider] for the same reason that one is
/// separate from the controller's own notifications: this changes ten times a
/// second while a call is up, and only one screen ever wants it.
final micLevelProvider = Provider<ValueListenable<MicLevel>>(
  (ref) => ref.watch(callControllerProvider).micLevel,
);
