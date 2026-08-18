// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// `AppExitResponse` is a dart:ui type; `show` keeps the rest of dart:ui from
// colliding with the widgets library imported below.
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import 'livekit_call_controller.dart';
import 'livekit_token_service.dart';
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

  // A slider drag has to be audible immediately, so any preference change
  // re-applies to the live tracks. `listen`, not `watch`: watching would
  // rebuild the controller and drop the call on every volume tweak.
  ref.listen(voicePrefsProvider, (_, _) => controller.onPrefsChanged());

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
      await controller
          .leave()
          .timeout(const Duration(seconds: 3), onTimeout: () {});
      return AppExitResponse.exit;
    },
  );

  ref.onDispose(lifecycle.dispose);
  ref.onDispose(controller.dispose);
  return controller;
});
