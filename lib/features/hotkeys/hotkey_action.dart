// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'hotkey.dart';

/// The things a global chord can do while a game has the foreground.
///
/// Each carries the id `RegisterHotKey` is called with, and those ids are
/// **persisted and must never be reused for a different action** — a stale
/// binding would otherwise start driving whatever inherited its number.
///
/// 1 and 2 are the overlay's own toggle and edit chords, bound separately in
/// `OverlayController`. They are listed here so the numbering is visible in one
/// place and nobody allocates over them.
enum HotkeyAction {
  toggleMute(3, 'Mute or unmute yourself'),
  toggleDeafen(4, 'Deafen or undeafen'),
  stopScreenShares(5, 'Stop sharing your screen');

  const HotkeyAction(this.id, this.label);

  /// Stable, persisted, and passed straight to `RegisterHotKey`.
  final int id;

  /// How the settings row names it.
  final String label;
}

/// Ids 1 and 2, which belong to the overlay and are not [HotkeyAction] values.
///
/// Declared here so the two schemes cannot collide by accident.
const Set<int> kOverlayHotkeyIds = {1, 2};

/// Nothing is bound out of the box.
///
/// Deliberately, and it is the same reasoning the overlay's chords are gated
/// on: registering a chord takes it away from every other program on the
/// machine for as long as it is held. Guessing at Alt+M on somebody's behalf
/// would mean silently breaking whatever already used it, in an app they had
/// not asked to do anything global yet.
const Map<HotkeyAction, Hotkey> kDefaultCallHotkeys = {};
