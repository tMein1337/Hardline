// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:http/http.dart' as http;

import '../voice/live_participant.dart';
import '../voice/speaking_participants.dart';
import 'overlay_channel.dart';
import 'overlay_layout.dart';
import 'overlay_prefs_state.dart';
import 'overlay_wire.dart';

/// The size the overlay's avatars are fetched at.
///
/// One request per person regardless of what the layout asks for, because the
/// layout can change without the roster doing so and re-fetching every face
/// because somebody dragged a slider would be absurd. The ceiling of
/// [kMaxOverlayAvatar] at 2x, so the largest allowed avatar is still sharp.
const _avatarPixels = 192;

/// Drives the overlay window from the app's state.
///
/// Deliberately free of Riverpod, like `LiveKitCallController`: everything it
/// needs arrives through callbacks and setters, so the decision logic — when to
/// show, which layout applies, what to push — can be exercised without a
/// container, a client or a live call.
///
/// It owns the difference between the two kinds of push. A snapshot carries
/// avatars and is sent when the roster, the layout or the theme changes; a
/// speaking update is a set of ids and is sent several times a second. Sending
/// the first at the second's rate would move a few hundred kilobytes a second
/// between two isolates to redraw a ring.
class OverlayController {
  OverlayController({
    required this.channel,
    required this.persistLayout,
    required this.fetchAvatar,
  }) {
    _subscriptions.addAll([
      channel.foregroundApp.listen(_onForegroundApp),
      channel.hotkeys.listen(_onHotkey),
      channel.edits.listen(_onOverlayEvent),
    ]);
  }

  final OverlayChannel channel;

  /// Writes a layout the user dragged into place back to preferences.
  final void Function(OverlayLayout layout) persistLayout;

  /// Resolves an `mxc://` to image bytes, or null when there is no avatar.
  final Future<Uint8List?> Function(String mxcUri, int pixels) fetchAvatar;

  final List<StreamSubscription<Object?>> _subscriptions = [];

  OverlayPrefsState _prefs = const OverlayPrefsState();
  OverlayPalette _palette = const OverlayPalette(
    speakingRing: 0xFFFF7A18,
    text: 0xFFFFFFFF,
    plate: 0xCC000000,
  );

  List<OverlayPerson> _people = const [];
  String _foregroundExecutable = '';
  bool _inCall = false;
  bool _editing = false;
  bool _shown = false;

  /// Pushed out of the way by the toggle chord, without switching the feature
  /// off.
  ///
  /// Runtime rather than stored, and deliberately not the same thing as
  /// `OverlayPrefsState.enabled`. If the chord flipped the *preference* it
  /// would unbind itself on the way down — the chord is only registered while
  /// the overlay is enabled — leaving a shortcut that can turn the HUD off and
  /// never back on. Sticky for the session, like the call/timeline toggle:
  /// somebody who wanted it out of the way probably still does next call.
  bool _hidden = false;

  /// The last snapshot actually sent, so an unchanged one is not re-sent.
  OverlaySnapshot? _lastSnapshot;
  OverlaySpeaking? _lastSpeaking;

  /// mxc uri to bytes. Avatars change about never, and re-fetching one per
  /// participant change would put an HTTP request behind every join.
  final Map<String, Uint8List?> _avatars = {};

  /// Bumped on every roster change, so a slow avatar fetch cannot finish after
  /// a newer one and put the older list back.
  int _generation = 0;

  /// Coalescing guard for [_reconcile]; see its doc comment.
  bool _reconcileInFlight = false;
  bool _reconcileDirty = false;

  bool _disposed = false;

  /// Whether the HUD is being laid out rather than watched.
  bool get editing => _editing;

  /// The layout in force for whatever is in front right now.
  OverlayLayout get activeLayout => _prefs.layoutFor(_foregroundExecutable);

  /// The application the next "use this layout here too" would apply to.
  String get foregroundExecutable => _foregroundExecutable;

  Future<void> dispose() async {
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await channel.unregisterHotkey(OverlayHotkeyId.toggle);
    await channel.unregisterHotkey(OverlayHotkeyId.edit);
    await channel.hide();
    await channel.dispose();
  }

  // ---------------------------------------------------------------------------
  // Inputs
  // ---------------------------------------------------------------------------

  Future<void> setPrefs(OverlayPrefsState prefs) async {
    final previous = _prefs;
    _prefs = prefs;

    // Switching the feature on always shows it. Otherwise a HUD hidden by the
    // chord three days ago would refuse to appear, from a setting that says it
    // is on, with nothing on screen to explain why.
    if (!previous.enabled && prefs.enabled) _hidden = false;

    await _applyHotkeys(previous, prefs);

    if (previous.monitorId != prefs.monitorId && _shown) {
      await channel.setMonitor(prefs.monitorId);
    }
    if (previous.excludeFromCapture != prefs.excludeFromCapture && _shown) {
      await channel.setCaptureExclusion(prefs.excludeFromCapture);
    }
    // Switching the overlay off has to leave edit mode with it, or the next
    // time it is switched on it comes up interactive over whatever is running.
    if (!prefs.enabled) _editing = false;

    await _reconcile();
  }

  bool _hotkeysBound = false;

  /// Binds the global chords, but **only while the overlay is switched on**.
  ///
  /// A registered hotkey is taken from every other program on the machine for
  /// as long as it is held. Holding two of them at all times for a feature
  /// somebody has turned off is not ours to do — it was, until this was
  /// noticed, and Alt+Shift+O stopped working everywhere else on the system.
  Future<void> _applyHotkeys(
    OverlayPrefsState previous,
    OverlayPrefsState prefs,
  ) async {
    if (!prefs.enabled) {
      if (_hotkeysBound) {
        await channel.unregisterHotkey(OverlayHotkeyId.toggle);
        await channel.unregisterHotkey(OverlayHotkeyId.edit);
        _hotkeysBound = false;
      }
      return;
    }

    if (!_hotkeysBound || previous.toggleHotkey != prefs.toggleHotkey) {
      await channel.registerHotkey(OverlayHotkeyId.toggle, prefs.toggleHotkey);
    }
    if (!_hotkeysBound || previous.editHotkey != prefs.editHotkey) {
      await channel.registerHotkey(OverlayHotkeyId.edit, prefs.editHotkey);
    }
    _hotkeysBound = true;
  }

  void setPalette(OverlayPalette palette) {
    if (_palette == palette) return;
    _palette = palette;
    unawaited(_reconcile());
  }

  /// The call changed: who is in it, or whether we are in one at all.
  Future<void> setParticipants({
    required bool inCall,
    required List<LiveParticipant> participants,
  }) async {
    _inCall = inCall;
    final generation = ++_generation;

    // One entry per *person*, not per device. Somebody in the call from a
    // laptop and a phone is one face on the HUD; the grid has room to draw both
    // and the overlay does not, and "which of their two devices" is not a
    // question a corner of a game screen should be asking.
    final seen = <String>{};
    final people = <({String userId, String name, String? mxc})>[];
    for (final participant in participants) {
      if (!seen.add(participant.userId)) continue;
      people.add((
        userId: participant.userId,
        name: participant.displayName,
        mxc: participant.avatarMxc,
      ));
    }

    // Fetched before the list is swapped in, so the HUD never appears with a
    // row of initials that fill in a moment later.
    for (final person in people) {
      final mxc = person.mxc;
      if (mxc == null || mxc.isEmpty || _avatars.containsKey(mxc)) continue;
      _avatars[mxc] = await fetchAvatar(mxc, _avatarPixels);
      // Somebody joined or left while that request was out. The cache entry is
      // still worth keeping — it is keyed by the avatar, not by the roster —
      // but this list is stale and the newer call owns the state now.
      if (_disposed || generation != _generation) return;
    }

    _people = [
      for (final person in people)
        OverlayPerson(
          userId: person.userId,
          name: person.name,
          avatar: person.mxc == null ? null : _avatars[person.mxc],
        ),
    ];

    await _reconcile();
  }

  /// The hot path, called several times a second while anybody is talking.
  void setSpeaking(SpeakingParticipants speaking) {
    final next = OverlaySpeaking(speaking.userIds);
    if (_lastSpeaking == next) return;
    _lastSpeaking = next;
    if (!_shown) return;
    unawaited(channel.pushState(next.encode()));
  }

  // ---------------------------------------------------------------------------
  // Reactions
  // ---------------------------------------------------------------------------

  void _onForegroundApp(ForegroundApp app) {
    if (app.executable == _foregroundExecutable) return;
    _foregroundExecutable = app.executable;
    // A different application may mean a different layout. It usually does not
    // — most executables are unassigned and share the default — and `_reconcile`
    // compares the snapshot before sending, so the usual case costs nothing.
    unawaited(_reconcile());
  }

  void _onHotkey(int id) {
    switch (id) {
      case OverlayHotkeyId.toggle:
        _hidden = !_hidden;
        // Coming back into view should not come back mid-edit.
        if (_hidden) _editing = false;
        unawaited(_reconcile());
      case OverlayHotkeyId.edit:
        _editing = !_editing;
        // Editing something that is hidden is not a state worth having.
        if (_editing) _hidden = false;
        unawaited(_reconcile());
    }
  }

  void _onOverlayEvent(String payload) {
    final message = decodeOverlayMessage(payload);
    if (message is! OverlayEdit) return;
    // Only position comes back from a drag; everything else about the layout is
    // edited in settings, where there is room for labelled controls.
    persistLayout(
      activeLayout.copyWith(x: message.layout.x, y: message.layout.y),
    );
  }

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  /// Brings the overlay to the state everything above implies.
  ///
  /// One place decides visibility, click-through and what has been pushed, for
  /// the reason `_reapplyAudioState` is one place: the inputs are independent
  /// and applying them as separate imperative steps produces ordering bugs that
  /// are miserable to find — an overlay left interactive after edit mode ended,
  /// or hidden after a call it was already showing.
  ///
  /// Coalesced the same way and for the same reason. Every input above calls
  /// this, several of them at LiveKit's event rate, and each pass crosses the
  /// method channel — so a pass already in flight sets a flag and exactly one
  /// more runs afterwards, with the final values. Without it two passes could
  /// both find `_shown` false and each bring a window up.
  Future<void> _reconcile() async {
    if (_reconcileInFlight) {
      _reconcileDirty = true;
      return;
    }
    _reconcileInFlight = true;
    try {
      do {
        _reconcileDirty = false;
        await _reconcileOnce();
      } while (_reconcileDirty && !_disposed);
    } finally {
      _reconcileInFlight = false;
    }
  }

  Future<void> _reconcileOnce() async {
    if (_disposed || !OverlayChannel.isSupported) return;

    // Edit mode is allowed outside a call, so the HUD can be arranged without
    // asking somebody else to join one and talk.
    final wanted = _prefs.enabled && !_hidden && (_inCall || _editing);

    if (!wanted) {
      if (_shown) {
        _shown = false;
        _lastSnapshot = null;
        await channel.hide();
      }
      return;
    }

    final snapshot = OverlaySnapshot(
      people: _people,
      layout: activeLayout,
      palette: _palette,
      editing: _editing,
    );

    if (!_shown) {
      _shown = await channel.show(
        monitorId: _prefs.monitorId,
        clickThrough: !_editing,
        excludeFromCapture: _prefs.excludeFromCapture,
        state: snapshot.encode(),
      );
      _lastSnapshot = _shown ? snapshot : null;
      // The window had no engine to push to until now, so whatever the last
      // speaking update said never arrived.
      if (_shown && _lastSpeaking != null) {
        await channel.pushState(_lastSpeaking!.encode());
      }
      return;
    }

    await channel.setClickThrough(!_editing);

    if (_lastSnapshot != snapshot) {
      _lastSnapshot = snapshot;
      await channel.pushState(snapshot.encode());
    }
  }
}

/// Resolves the palette the HUD draws with from the app's own theme.
///
/// Sent across rather than looked up on the far side: the overlay isolate would
/// otherwise have to load the theme system, the preferences and the palette
/// files a second time to arrive at the same three colours.
OverlayPalette overlayPaletteFrom({
  required Color speakingRing,
  required Color text,
  required Color plate,
}) => OverlayPalette(
  speakingRing: speakingRing.toARGB32(),
  text: text.toARGB32(),
  plate: plate.toARGB32(),
);

/// Fetches an avatar thumbnail as bytes.
///
/// Free function so the controller can be handed something else in a test.
/// Returns null for anything that does not resolve, which the HUD draws as
/// initials — exactly what `MxAvatar` does with an unreachable avatar.
Future<Uint8List?> fetchAvatarBytes(
  Uri? uri,
  Map<String, String> headers,
) async {
  if (uri == null) return null;
  try {
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) return null;
    return response.bodyBytes;
  } catch (error) {
    debugPrint('[overlay] avatar fetch failed: $error');
    return null;
  }
}
