// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'hotkey.dart';

/// What has to be true before a chord is worth holding.
///
/// A registered chord is taken from every other program on the machine for as
/// long as it is held, so "should this be bound at all right now" is a real
/// question and not every action answers it the same way.
enum HotkeyGate {
  /// Held for as long as the application runs.
  ///
  /// Right for anything whose action is always available. A mute chord cannot
  /// be gated on a call being live: the chord has to already exist at the
  /// moment somebody wants to use it, and binding it on join would mean the
  /// first press of every call did nothing.
  always,

  /// Held only while the overlay feature is switched on.
  ///
  /// The overlay's chords do nothing whatsoever when the feature is off, so
  /// holding them then is pure cost to everything else on the machine. This is
  /// not hypothetical — it used to hold both at all times, and Alt+Shift+O
  /// stopped working everywhere else on the system.
  overlayEnabled,
}

/// The things a global chord can do while a game has the foreground.
///
/// Each carries the id `RegisterHotKey` is called with, and those ids are
/// **persisted and must never be reused for a different action** — a stale
/// binding would otherwise start driving whatever inherited its number.
///
/// Ids 1 and 2 belonged to the overlay, which registered and dispatched them
/// itself from `OverlayController`. They are the same two actions and the same
/// two numbers; what changed is that one registry now owns every chord, so a
/// chord bound twice can be *named* rather than merely refused. Windows turns
/// down the second registration of a chord whoever asks — measured, in
/// `integration_test/hotkeys_flow.dart` — and all it says is no; with two
/// stores, neither half could tell that the program in the way was this one.
enum HotkeyAction {
  overlayToggle(1, 'Hide and show the overlay', HotkeyGate.overlayEnabled),
  overlayEdit(2, 'Move the overlay', HotkeyGate.overlayEnabled),
  toggleMute(3, 'Mute or unmute yourself', HotkeyGate.always),
  toggleDeafen(4, 'Deafen or undeafen', HotkeyGate.always),
  stopScreenShares(5, 'Stop sharing your screen', HotkeyGate.always);

  const HotkeyAction(this.id, this.label, this.gate);

  /// Stable, persisted, and passed straight to `RegisterHotKey`.
  final int id;

  /// How the settings row names it.
  final String label;

  /// See [HotkeyGate].
  final HotkeyGate gate;

  /// The actions the voice pane lists: everything not tied to the overlay.
  ///
  /// The overlay's two are configured in their own pane beside the rest of the
  /// overlay, where the setting that gates them also lives. Listing all five
  /// in both places would mean two rows for one binding.
  static Iterable<HotkeyAction> get alwaysOn =>
      values.where((action) => action.gate == HotkeyGate.always);

  /// The overlay's own two, in the order its pane draws them.
  static Iterable<HotkeyAction> get overlay =>
      values.where((action) => action.gate == HotkeyGate.overlayEnabled);

  /// The action owning [id], or null for a number nothing claims.
  static HotkeyAction? byId(int id) =>
      values.where((action) => action.id == id).firstOrNull;
}

/// What a fresh installation starts with.
///
/// **The overlay's two are bound and the call actions are not**, which looks
/// inconsistent and is not. The difference is [HotkeyGate]: the overlay's
/// chords are only held while the overlay is switched on, and the overlay
/// ships off, so a default costs other programs nothing until somebody asks
/// for the feature. A call chord is held from launch, so guessing at Alt+M on
/// somebody's behalf would silently break whatever already used it, in an app
/// they had not asked to do anything global yet.
///
/// Alt+Shift+O and Alt+Shift+P are the pair the overlay has always shipped
/// with, kept here so moving the store does not quietly unbind them.
const Map<HotkeyAction, Hotkey> kDefaultHotkeys = {
  HotkeyAction.overlayToggle: Hotkey(
    modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
    key: 0x4F, // O
  ),
  HotkeyAction.overlayEdit: Hotkey(
    modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
    key: 0x50, // P
  ),
};
