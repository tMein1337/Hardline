// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/matrix/avatar_uri_provider.dart';
import '../../theme/theme_controller.dart';
import '../voice/call_controller_provider.dart';
import 'overlay_channel.dart';
import 'overlay_controller.dart';
import 'overlay_prefs_controller.dart';

/// Owns the one [OverlayController].
///
/// App-scoped and never auto-disposed, like `callControllerProvider` and for
/// the same reason: it holds a native window and a second Flutter engine, and
/// tearing those down because nothing happened to be watching would make the
/// overlay flicker every time the settings screen closed.
final overlayControllerProvider = Provider<OverlayController>((ref) {
  final controller = OverlayController(
    channel: OverlayChannel(),
    persistLayout: (layout) =>
        ref.read(overlayPrefsProvider.notifier).updateLayout(layout),
    fetchAvatar: (mxcUri, pixels) async {
      // The same resolver the rest of the app uses, so the overlay gets the
      // thumbnail already in cache rather than a second copy at a size nothing
      // else asked for.
      final uri = await ref.read(
        avatarUriProvider(AvatarRequest(mxcUri: mxcUri, size: pixels)).future,
      );
      return fetchAvatarBytes(uri, ref.read(mediaRequestHeaders));
    },
  );

  ref.onDispose(() => unawaited(controller.dispose()));
  return controller;
});

/// Feeds the overlay everything it draws.
///
/// A `Provider<void>` mounted for its side effects, the shape
/// `staleMembershipSweepProvider` uses. Watched from `BackgroundWorkers`, so
/// the overlay is driven from the first sync rather than from whenever its
/// settings pane is first opened.
///
/// Two of its four inputs are listenables rather than provider state — the call
/// controller is a `ChangeNotifier` and `speaking` is a `ValueNotifier` — so
/// they are hooked by hand and released in `onDispose`. Watching them as
/// providers is not an option: `speaking` changes several times a second, and
/// rebuilding this provider at that rate would re-register the hotkeys with it.
final overlayDriverProvider = Provider<void>((ref) {
  final controller = ref.watch(overlayControllerProvider);

  unawaited(controller.setPrefs(ref.watch(overlayPrefsProvider)));

  final palette = ref.watch(paletteProvider);
  controller.setPalette(
    overlayPaletteFrom(
      speakingRing: palette.voiceSpeakingRing,
      text: palette.textPrimary,
      // The scrim is what the rest of the app puts behind text that has to
      // stay readable over something it does not control. A game is the
      // strongest case of that there is.
      plate: palette.scrim,
    ),
  );

  final call = ref.watch(callControllerProvider);
  void onCallChanged() => unawaited(
    controller.setParticipants(
      inCall: call.isInCall,
      participants: call.participants,
    ),
  );
  call.addListener(onCallChanged);
  ref.onDispose(() => call.removeListener(onCallChanged));
  onCallChanged();

  final speaking = ref.watch(speakingParticipantsProvider);
  void onSpeakingChanged() => controller.setSpeaking(speaking.value);
  speaking.addListener(onSpeakingChanged);
  ref.onDispose(() => speaking.removeListener(onSpeakingChanged));
  onSpeakingChanged();
});
