// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'hotkey.dart';
import 'hotkey_action.dart';

/// Which chord runs which action. The only store of that, for every chord.
///
/// A map rather than a field per action, which is what `OverlayPrefsState`
/// used to hold for its two: actions are expected to be added, and a shape that
/// costs five edits per new one is a shape that eventually gets a new one wired
/// up wrong. The overlay's pair proved it — they were named fields, so they
/// were registered and dispatched by hand in a second place that no conflict
/// check could see.
///
/// An action with no entry is unbound. That is the shipped state for the call
/// actions and not for the overlay's; [kDefaultHotkeys] explains why the two
/// differ.
@immutable
class HotkeysState {
  const HotkeysState({this.bindings = kDefaultHotkeys});

  /// Reads whatever it can and drops the rest.
  ///
  /// Tolerant on purpose. This is user preference, not protocol: a value that
  /// cannot be understood should cost its own binding and nothing else, and
  /// must never take the settings pane down with it.
  factory HotkeysState.fromJson(Map<String, Object?> json) {
    final bindings = <HotkeyAction, Hotkey>{};

    for (final action in HotkeyAction.values) {
      final raw = json[action.name];
      if (raw is! Map) continue;
      final hotkey = Hotkey.fromJson(raw.cast<String, Object?>());
      // An unbound chord is the same as no entry, and storing it as one keeps
      // `isBound` from having to be asked twice.
      if (hotkey.isBound) bindings[action] = hotkey;
    }

    return HotkeysState(bindings: bindings);
  }

  final Map<HotkeyAction, Hotkey> bindings;

  Hotkey? operator [](HotkeyAction action) => bindings[action];

  bool get hasAny => bindings.isNotEmpty;

  HotkeysState withBinding(HotkeyAction action, Hotkey? hotkey) {
    final next = Map<HotkeyAction, Hotkey>.from(bindings);
    if (hotkey == null || !hotkey.isBound) {
      next.remove(action);
    } else {
      next[action] = hotkey;
    }
    return HotkeysState(bindings: next);
  }

  Map<String, Object?> toJson() => {
    for (final entry in bindings.entries) entry.key.name: entry.value.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HotkeysState && mapEquals(bindings, other.bindings);

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final entry in bindings.entries) Object.hash(entry.key, entry.value),
  ]);
}
