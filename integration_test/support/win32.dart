// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The handful of Win32 calls an integration test needs to check what the
/// *operating system* thinks happened, rather than what the app believes.
///
/// A widget test can only ask the app. That is the wrong witness for anything
/// in `windows/runner/`: a chord the binder is convinced it registered, a
/// window the controller is convinced is transparent. These ask Windows.
///
/// Bound by hand over `dart:ffi` instead of through `package:win32`, because a
/// dependency for a dozen functions would have to be carried through the
/// licence notices and the Nix packaging to serve a test.
library;

import 'dart:ffi';

final _user32 = DynamicLibrary.open('user32.dll');

final _registerHotKey = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Uint32, Uint32),
      int Function(int, int, int, int)
    >('RegisterHotKey');

final _unregisterHotKey = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'UnregisterHotKey',
    );

final _keybdEvent = _user32
    .lookupFunction<
      Void Function(Uint8, Uint8, Uint32, IntPtr),
      void Function(int, int, int, int)
    >('keybd_event');

const _keyUp = 0x0002;

const _vkShift = 0x10;
const _vkControl = 0x11;
const _vkAlt = 0x12;

/// The `MOD_*` bits, which are also what `Hotkey.modifiers` stores.
const modAlt = 0x1;
const modControl = 0x2;
const modShift = 0x4;

/// Ids for the registrations this file makes itself.
///
/// Far above anything `HotkeyAction` allocates, and registered against the
/// calling thread rather than the runner's message window, so they can never
/// be mistaken for one of the app's.
const _probeId = 0x7F00;
var _nextHeldId = 0x7F01;

/// Whether nothing on the machine currently holds this chord.
///
/// Asked the only way Windows allows: by trying to take it. `RegisterHotKey`
/// fails for a chord that is already registered — by another program or by
/// this one under a different id — so a registration that succeeds is released
/// again at once and reported as free.
bool chordIsFree(int modifiers, int key) {
  if (_registerHotKey(0, _probeId, modifiers, key) == 0) return false;
  _unregisterHotKey(0, _probeId);
  return true;
}

/// Takes a chord and keeps it, standing in for another program that got there
/// first. Returns a function that lets go of it, or null if it was not free.
void Function()? holdChord(int modifiers, int key) {
  final id = _nextHeldId++;
  if (_registerHotKey(0, id, modifiers, key) == 0) return null;
  return () => _unregisterHotKey(0, id);
}

/// Presses a chord on the real keyboard, as far as Windows can tell.
///
/// Injected input goes through the same path as a key somebody pressed, which
/// is the point: a registered chord is consumed by the window manager and
/// arrives as `WM_HOTKEY` at the runner's message window, exactly as it would
/// from inside a game.
void pressChord(int modifiers, int key) {
  final held = [
    if (modifiers & modControl != 0) _vkControl,
    if (modifiers & modAlt != 0) _vkAlt,
    if (modifiers & modShift != 0) _vkShift,
  ];
  for (final modifier in held) {
    _keybdEvent(modifier, 0, 0, 0);
  }
  _keybdEvent(key, 0, 0, 0);
  _keybdEvent(key, 0, _keyUp, 0);
  for (final modifier in held.reversed) {
    _keybdEvent(modifier, 0, _keyUp, 0);
  }
}
