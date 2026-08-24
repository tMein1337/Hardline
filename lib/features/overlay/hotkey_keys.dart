// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';

import 'overlay_layout.dart';

/// Translates a key press into the virtual-key code `RegisterHotKey` wants.
///
/// Deliberately narrow: letters, digits and the function keys, and nothing
/// else. A global chord is registered process-wide and taken away from every
/// other program on the machine, so the set it can be built from should be the
/// set people actually expect to bind — not every key Windows has a number for,
/// including the ones a game needs.
///
/// Returns null for anything outside that set, which the capture field shows as
/// "not a key that can be bound" rather than silently accepting and failing at
/// registration time.
int? virtualKeyFor(LogicalKeyboardKey key) {
  final id = key.keyId;

  // Letters. Flutter reports the lowercase codepoint; Win32 virtual-key codes
  // for letters are the uppercase ASCII values.
  const lowerA = 0x61;
  const lowerZ = 0x7A;
  if (id >= lowerA && id <= lowerZ) return id - 0x20;

  // Digits, where the two agree already.
  const zero = 0x30;
  const nine = 0x39;
  if (id >= zero && id <= nine) return id;

  // `LogicalKeyboardKey` overrides `==`, which rules out a const map, and the
  // function keys are not a contiguous range in Flutter's numbering the way
  // they are in Win32's. A dozen comparisons on a key press is nothing.
  final index = _functionKeys.indexOf(key);
  return index < 0 ? null : 0x70 + index;
}

/// A chord, spelled the way it would be written down.
String hotkeyLabel(OverlayHotkey hotkey) {
  if (!hotkey.isBound) return 'Not set';

  final parts = <String>[
    if (hotkey.modifiers & HotkeyModifier.control != 0) 'Ctrl',
    if (hotkey.modifiers & HotkeyModifier.alt != 0) 'Alt',
    if (hotkey.modifiers & HotkeyModifier.shift != 0) 'Shift',
    _keyName(hotkey.key),
  ];
  return parts.join(' + ');
}

/// The modifier bits currently held down, in Win32 terms.
int modifiersFrom(Set<LogicalKeyboardKey> pressed) {
  var modifiers = 0;
  if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight)) {
    modifiers |= HotkeyModifier.control;
  }
  if (pressed.contains(LogicalKeyboardKey.altLeft) ||
      pressed.contains(LogicalKeyboardKey.altRight)) {
    modifiers |= HotkeyModifier.alt;
  }
  if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight)) {
    modifiers |= HotkeyModifier.shift;
  }
  return modifiers;
}

/// Whether a chord is worth offering to Windows.
///
/// A bare letter would be swallowed globally — every time it was typed, in any
/// program — so at least one modifier is required. Function keys are exempt:
/// F13 and up do not appear on most keyboards, but F1 to F12 with no modifier
/// is a binding people genuinely make for a push-to-talk-shaped control, and
/// refusing it would be us deciding for them.
bool isBindable(OverlayHotkey hotkey) {
  if (!hotkey.isBound) return false;
  if (hotkey.modifiers != 0) return true;
  return hotkey.key >= 0x70 && hotkey.key <= 0x7B;
}

String _keyName(int virtualKey) {
  if (virtualKey >= 0x41 && virtualKey <= 0x5A) {
    return String.fromCharCode(virtualKey);
  }
  if (virtualKey >= 0x30 && virtualKey <= 0x39) {
    return String.fromCharCode(virtualKey);
  }
  if (virtualKey >= 0x70 && virtualKey <= 0x7B) {
    return 'F${virtualKey - 0x6F}';
  }
  return 'Key $virtualKey';
}

/// F1 to F12, in order, so the index is the offset from `VK_F1`.
final _functionKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
];
