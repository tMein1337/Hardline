// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// A global chord, in the Win32 terms the runner needs.
///
/// Stored as `MOD_*` and virtual-key numbers rather than as anything friendlier
/// because that is what `RegisterHotKey` takes, and translating twice is two
/// places for a mapping to be wrong.
@immutable
class Hotkey {
  const Hotkey({required this.modifiers, required this.key});

  /// Nothing bound. Registering this is a no-op rather than an error.
  const Hotkey.none() : modifiers = 0, key = 0;

  factory Hotkey.fromJson(Map<String, Object?> json) => Hotkey(
    modifiers: json['modifiers'] is int ? json['modifiers']! as int : 0,
    key: json['key'] is int ? json['key']! as int : 0,
  );

  /// A bitmask of `MOD_ALT` (1), `MOD_CONTROL` (2), `MOD_SHIFT` (4).
  final int modifiers;

  /// A Win32 virtual-key code. Zero means unbound.
  final int key;

  bool get isBound => key != 0;

  Map<String, Object?> toJson() => {'modifiers': modifiers, 'key': key};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hotkey && modifiers == other.modifiers && key == other.key;

  @override
  int get hashCode => Object.hash(modifiers, key);
}

/// Win32 modifier bits, so nothing has to remember which number is which.
abstract final class HotkeyModifier {
  static const alt = 1;
  static const control = 2;
  static const shift = 4;
}
