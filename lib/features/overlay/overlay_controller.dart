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
    plate: 0xFF08080A,
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

  /// Numbers each *sending* of a snapshot; see `OverlaySnapshot.encode`.
  int _serial = 0;

  /// The sending the window was last shown for.
  ///
  /// The window gets no opacity until the overlay reports that one — or a
  /// later one — drawn. See [_onDrawn].
  int _revealSerial = 0;

  /// Whether the overlay has drawn what the window was shown for.
  bool _revealed = false;

  /// Set when the overlay isolate announces itself, so the next pass sends it
  /// who is speaking as well as the roster. See [_onReady].
  bool _resendSpeaking = false;

  /// Whether the overlay isolate has ever been heard from in this session.
  bool _engineSeen = false;

  /// Running since the last `show` returned, for the log lines that say how
  /// long the engine took to come up and to draw.
  Stopwatch? _sinceShow;

  /// Fires if a shown window is never drawn into. See [_armRevealWatchdog].
  Timer? _revealWatchdog;

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
    _lingerTimer?.cancel();
    _lingerTimer = null;
    _revealWatchdog?.cancel();
    _revealWatchdog = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await channel.hide();
    // Deliberately not `channel.dispose()`. The channel is shared — see
    // `overlayChannelProvider` — and closing it here would take the hotkey
    // binder's subscription down with it.
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

  void setPalette(OverlayPalette palette) {
    if (_palette == palette) return;
    _palette = palette;
    // The runner has to know the key before the HUD paints with it. Chained
    // rather than fired alongside: a reconcile that pushed the new palette
    // first would give the overlay a frame painting a colour the window is
    // not keying, which is an opaque sheet over the game.
    unawaited(
      channel.setChromaKey(palette.chromaKey).then((_) => _reconcile()),
    );
  }

  /// The call changed: who is in it, or whether we are in one at all.
  Future<void> setParticipants({
    required bool inCall,
    required List<LiveParticipant> participants,
  }) async {
    // Said once per call, at the moment it starts, because "the overlay did
    // not appear" has three answers that look identical from the outside and
    // only one of them is a bug: it is switched off, it was pushed away with
    // the chord, or it should be there and is not.
    if (inCall && !_inCall && OverlayChannel.isSupported) {
      debugPrint(
        '[overlay] call joined: '
        '${!_prefs.enabled
            ? 'not showing, the overlay is switched off'
            : _hidden
            ? 'not showing, it was hidden with the toggle chord'
            : 'showing'}',
      );
    }
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

    // Drawn first, with whatever avatars are already cached, and *then* the
    // missing ones are fetched.
    //
    // This used to be the other way round, so that the HUD never appeared with
    // a row of initials that filled in a moment later. That preference cost
    // the whole feature on the first call of a session: nothing is cached yet,
    // so every avatar is a real HTTP request, and the overlay could not appear
    // until all of them had come back. Worse, each superseding update returns
    // early below — correctly, the newer roster owns the state — so a
    // participant list that changes while a fetch is out, which is exactly
    // what a call does while it connects, abandoned the reconcile with it.
    // The overlay simply never came up until the next call, by which point the
    // avatars were cached and it was instant.
    //
    // A face that arrives a beat late is a far smaller thing than an overlay
    // that does not arrive at all.
    _people = _describe(people);
    await _reconcile();

    var filled = false;
    for (final person in people) {
      final mxc = person.mxc;
      if (mxc == null || mxc.isEmpty || _avatars.containsKey(mxc)) continue;
      _avatars[mxc] = await fetchAvatar(mxc, _avatarPixels);
      // Somebody joined or left while that request was out. The cache entry is
      // still worth keeping — it is keyed by the avatar, not by the roster —
      // but this list is stale and the newer call owns the state now.
      if (_disposed || generation != _generation) return;
      filled = true;
    }

    // Nothing arrived that the first pass did not already have.
    if (!filled) return;

    _people = _describe(people);
    await _reconcile();
  }

  List<OverlayPerson> _describe(
    List<({String userId, String name, String? mxc})> people,
  ) => [
    for (final person in people)
      OverlayPerson(
        userId: person.userId,
        name: person.name,
        avatar: person.mxc == null ? null : _avatars[person.mxc],
      ),
  ];

  /// The hot path, called several times a second while anybody is talking.
  void setSpeaking(SpeakingParticipants speaking) {
    final next = OverlaySpeaking(speaking.userIds);
    if (_lastSpeaking == next) return;
    _lastSpeaking = next;
    if (!_shown) return;
    unawaited(channel.pushState(next.encode()));
    _onSpeechChanged(speaking.userIds.isNotEmpty);
  }

  // ---------------------------------------------------------------------------
  // Fade
  //
  // The HUD's opacity is a property of the *window*, not of the widgets. A
  // layered window has no per-pixel alpha to give them — see `kChromaKey` — so
  // everything is drawn solid and the window dims as a whole.
  //
  // Which would snap the roster to its idle opacity the instant a sentence
  // ended, and an ordinary conversation is full of instants like that. The
  // linger is what stops it flickering: the HUD stays up for `prefs.linger`
  // after the last person stops, and only then fades.
  // ---------------------------------------------------------------------------

  /// Pending drop to idle. Restarted whenever somebody speaks again.
  Timer? _lingerTimer;

  /// The last value sent, so a tick that changes nothing costs no channel call.
  int? _sentOpacity;

  /// Whether anybody was talking as of the last update.
  ///
  /// Kept because the opacity has to be recomputed at moments that are not
  /// speech changes — leaving edit mode, and the settings sliders moving — and
  /// those need to know which of the two values applies without disturbing a
  /// linger that is already running.
  bool _speakingNow = false;

  void _onSpeechChanged(bool anybodySpeaking) {
    _speakingNow = anybodySpeaking;
    _lingerTimer?.cancel();

    // Arranging a HUD that fades out from under the pointer is not arranging
    // anything. Edit mode holds it at full until it ends, and `_reconcileOnce`
    // re-applies that whenever edit mode is entered.
    if (anybodySpeaking) {
      _applyOpacity(_activeOpacityByte);
      return;
    }

    // Edit mode is the one case that ignores both settings. Arranging a HUD
    // somebody has set to 20% means arranging something they can barely see,
    // and the point of edit mode is to see it.
    if (_editing) {
      _applyOpacity(255);
      return;
    }

    // Held rather than dropped now. Restarting the timer on every new speaker
    // is what makes a conversation read as one continuous stretch of talking
    // rather than as one fade per sentence.
    _lingerTimer = Timer(_prefs.linger, () {
      _lingerTimer = null;
      _applyOpacity(_idleOpacityByte);
    });
  }

  /// The idle opacity of whichever layout is in force, as a byte.
  int get _idleOpacityByte =>
      (activeLayout.idleOpacity.clamp(0.0, 1.0) * 255).round();

  /// The same, for while somebody is talking.
  int get _activeOpacityByte =>
      (activeLayout.activeOpacity.clamp(0.0, 1.0) * 255).round();

  /// Recomputes the window's opacity from the current state.
  ///
  /// Distinct from [_onSpeechChanged], which *is* a speech change and restarts
  /// the linger. This one answers "what should it be right now" without
  /// touching the timer, and exists for the two moments that change the answer
  /// while nobody has started or stopped talking:
  ///
  ///  * **Leaving edit mode.** Edit mode pins the window at full, and nothing
  ///    put it back afterwards — so once a HUD had been arranged it stayed at
  ///    full opacity for the rest of the session. That is why toggling the
  ///    edit chord looked like it "refreshed" the overlay.
  ///  * **The opacity sliders.** The value was stored and never pushed, so
  ///    moving one did nothing at all until the next time somebody spoke.
  /// Adopts [layout] now, without waiting for it to arrive through prefs.
  ///
  /// The settings pane calls this when a slider is released. Writing the
  /// preference and then asking the controller to re-evaluate does not work on
  /// its own: the write updates provider state, `setPrefs` reaches this object
  /// a rebuild later, and a `refreshOpacity()` called in between computes the
  /// *old* value. The symptom was an opacity that only took effect when
  /// something else happened to trigger a reconcile — closing the settings
  /// screen, which changes the foreground application.
  ///
  /// Taking the layout directly removes the ordering question entirely. The
  /// prefs copy catches up a moment later with the same content.
  void applyLayoutNow(OverlayLayout layout) {
    _prefs = _prefs.copyWith(
      layouts: [
        for (final existing in _prefs.layouts)
          existing.id == layout.id ? layout : existing,
      ],
    );
    refreshOpacity();
    unawaited(_reconcile());
  }

  void refreshOpacity() {
    if (!_shown) return;
    if (_editing) {
      _applyOpacity(255);
      return;
    }
    // Still inside the linger counts as talking: the point of the hold is
    // that the HUD has not dropped yet.
    if (_speakingNow || _lingerTimer != null) {
      _applyOpacity(_activeOpacityByte);
      return;
    }
    _applyOpacity(_idleOpacityByte);
  }

  void _applyOpacity(int alpha) {
    // Nothing at all until the overlay has drawn what the window was shown
    // for. Whatever the settings say, a window whose contents are not the
    // current call's is not one to make visible — see [_onDrawn], which is
    // what recomputes the real value once it is.
    final effective = _revealed ? alpha : 0;
    if (_sentOpacity == effective) return;
    _sentOpacity = effective;
    unawaited(channel.setOpacity(effective));
  }

  // ---------------------------------------------------------------------------
  // The overlay talking back
  //
  // The window and the engine inside it are two things, and for a long time
  // this class treated one as evidence of the other: `show` returned, so the
  // HUD was assumed to be on screen. It was not, on the first call after every
  // launch. `show` creates the engine, and the snapshot handed to it arrived
  // before the engine's Dart had started listening — as did the speaking
  // update sent straight afterwards. A platform channel nobody is listening on
  // keeps one message, so the second pushed out the first, and the overlay
  // came up holding who was speaking and no idea who was in the call. Every
  // later call found the engine already running and worked.
  //
  // It only happened in an AOT build. In a debug build creating the engine
  // loads the kernel on the calling thread, which takes long enough that the
  // far side is listening by the time anything else is sent — so it never
  // once reproduced under `flutter run`, which is where it was being chased.
  //
  // Two things make it not depend on timing at all. The overlay installs its
  // handler before `runApp` rather than from a widget, and it *says* when it
  // is listening and when it has drawn, so this side acts on what happened
  // instead of on what it sent.
  // ---------------------------------------------------------------------------

  /// The overlay isolate is listening, so send it everything.
  ///
  /// Whatever was pushed before this may have been dropped, and there is no
  /// way to ask. Sending the state again costs one snapshot per engine start.
  void _onReady() {
    _engineSeen = true;
    final since = _sinceShow;
    debugPrint(
      '[overlay] engine ready'
      '${since == null ? '' : ' ${since.elapsedMilliseconds}ms after show'}',
    );
    _lastSnapshot = null;
    _resendSpeaking = true;
    unawaited(_reconcile());
  }

  /// The overlay has put snapshot [serial] on screen.
  ///
  /// This, and not `show` returning, is what makes the window visible. Before
  /// it the window holds whatever the engine last painted, and none of the
  /// possibilities is worth looking at: nothing while the engine boots; the
  /// compiled-in colour key before the first snapshot lands, which in any
  /// theme but the shipped one is an opaque sheet over the monitor; or the
  /// roster of the previous call, for the frame or two before the new one
  /// replaces it.
  void _onDrawn(int serial) {
    if (!_shown || _revealed || serial < _revealSerial) return;
    _revealed = true;
    _revealWatchdog?.cancel();
    _revealWatchdog = null;
    final since = _sinceShow;
    if (since != null) {
      debugPrint('[overlay] drawn ${since.elapsedMilliseconds}ms after show');
    }

    // Comes up as though somebody were talking, then settles to idle once the
    // linger runs out. Coming up already faded would look like the overlay
    // had failed to appear; coming up at full when the user has chosen a
    // dimmer talking opacity would announce it with a flash of exactly the
    // brightness they asked it not to use.
    //
    // The linger starts here rather than at `show`, so the time the engine
    // spent starting is not taken out of the time the HUD is on screen.
    _applyOpacity(_editing ? 255 : _activeOpacityByte);
    _onSpeechChanged(_lastSpeaking?.userIds.isNotEmpty ?? false);
  }

  /// Says so if a window that was shown is never drawn into.
  ///
  /// The window stays at zero opacity in that case, which is the right thing
  /// for it to do and also completely silent — the overlay is switched on, a
  /// call is up, and nothing appears. This is the line that tells the two
  /// apart from a setting.
  void _armRevealWatchdog() {
    _revealWatchdog?.cancel();
    _revealWatchdog = Timer(const Duration(seconds: 5), () {
      _revealWatchdog = null;
      if (_disposed || !_shown || _revealed) return;
      debugPrint(
        '[overlay] the window is up but nothing has been drawn into it for '
        '5s, so it is being left invisible rather than covering the screen. '
        '${_engineSeen ? 'The overlay engine did announce itself: it is running and '
                  'not drawing.' : 'The overlay engine never announced itself. If the log has '
                  '"Could not resolve main entrypoint function", '
                  '`overlayMain` is missing from the library that holds '
                  '`main`.'}',
      );
    });
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

  /// Pushes the HUD out of the way, or brings it back.
  ///
  /// Public because the chord that drives it is no longer registered here —
  /// `HotkeyBinder` owns every global chord and calls this one. The gating that
  /// used to live beside the registration moved with it, as a per-action gate;
  /// see `HotkeyGate.overlayEnabled`.
  void toggleHidden() {
    _hidden = !_hidden;
    // Coming back into view should not come back mid-edit.
    if (_hidden) _editing = false;
    unawaited(_reconcile());
  }

  /// Enters or leaves the mode where the HUD can be dragged into place.
  ///
  /// Public because the chord is not the only thing that should be able to
  /// reach it, and because "what happens on the way out" is worth a test —
  /// leaving edit mode used to leave the window pinned at full opacity for
  /// the rest of the session.
  void setEditing(bool editing) {
    if (_editing == editing) return;
    _editing = editing;
    // Editing something that is hidden is not a state worth having.
    if (_editing) _hidden = false;
    unawaited(_reconcile());
  }

  void _onOverlayEvent(String payload) {
    switch (decodeOverlayMessage(payload)) {
      case OverlayReady():
        _onReady();
      case OverlayDrawn(:final serial):
        _onDrawn(serial);
      case OverlayEdit(:final layout):
        // Only position comes back from a drag; everything else about the
        // layout is edited in settings, where there is room for labelled
        // controls.
        persistLayout(activeLayout.copyWith(x: layout.x, y: layout.y));
    }
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
        // The window keeps whatever opacity it had, and the next `show` is a
        // different call in a different state — so the cached value has to go
        // or the first frame back could be sent nothing and stay faded.
        _lingerTimer?.cancel();
        _lingerTimer = null;
        _sentOpacity = null;
        _revealed = false;
        _revealWatchdog?.cancel();
        _revealWatchdog = null;
        _sinceShow = null;
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
      // Before the window exists, so its very first frame is keyed correctly.
      await channel.setChromaKey(_palette.chromaKey);

      final serial = ++_serial;
      _revealSerial = serial;
      _revealed = false;
      final clock = Stopwatch()..start();
      // At zero opacity. The window being up says nothing about what is in
      // it; [_onDrawn] raises it once the overlay has drawn this snapshot.
      _shown = await channel.show(
        monitorId: _prefs.monitorId,
        clickThrough: !_editing,
        excludeFromCapture: _prefs.excludeFromCapture,
        opacity: 0,
        state: snapshot.encode(serial: serial),
      );
      // Unconditional, and one line per call. The first `show` of a session
      // is the one that starts a second Flutter engine, and how long that took
      // — or that it failed — is the first thing to want when the overlay did
      // not appear.
      debugPrint(
        '[overlay] show ${_shown ? 'returned' : 'FAILED'} after '
        '${clock.elapsedMilliseconds}ms'
        '${_engineSeen ? '' : ' (first of this session, starts the engine)'}',
      );
      _lastSnapshot = _shown ? snapshot : null;
      if (!_shown) return;

      _sentOpacity = 0;
      _sinceShow = clock;
      _armRevealWatchdog();
      // The window had no engine to push to until now, so whatever the last
      // speaking update said never arrived.
      _resendSpeaking = false;
      if (_lastSpeaking != null) {
        await channel.pushState(_lastSpeaking!.encode());
      }
      return;
    }

    await channel.setClickThrough(!_editing);

    // Both directions. Entering edit mode pins the window at full; leaving it
    // has to hand the opacity back to the settings, which nothing did.
    if (_editing) {
      _lingerTimer?.cancel();
      _lingerTimer = null;
    }
    refreshOpacity();

    if (_lastSnapshot != snapshot) {
      _lastSnapshot = snapshot;
      await channel.pushState(snapshot.encode(serial: ++_serial));
    }
    // After the roster, never before it: the overlay draws a ring around
    // somebody it has been told about.
    if (_resendSpeaking) {
      _resendSpeaking = false;
      if (_lastSpeaking != null) {
        await channel.pushState(_lastSpeaking!.encode());
      }
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
    // Bounded, because this runs in the middle of a roster update and an
    // unbounded `http.get` against a media endpoint that has gone away holds
    // the rest of that update behind it. Initials are a perfectly good answer
    // and arrive instantly; a picture is not worth waiting on.
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;
    return response.bodyBytes;
  } catch (error) {
    debugPrint('[overlay] avatar fetch failed: $error');
    return null;
  }
}
