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
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');

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

// ---------------------------------------------------------------------------
// Memory
//
// `dart:ffi` has no allocator of its own; `package:ffi` is where `calloc`
// lives. Two kernel32 calls stand in for it.
// ---------------------------------------------------------------------------

final _localAlloc = _kernel32
    .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
      'LocalAlloc',
    );

final _localFree = _kernel32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('LocalFree');

/// Zeroed memory, handed to [body] and freed whatever it does.
T _withMemory<T>(int bytes, T Function(Pointer<Uint8> memory) body) {
  // LPTR: fixed, and zero-initialised.
  final address = _localAlloc(0x0040, bytes);
  if (address == 0) throw StateError('LocalAlloc($bytes) failed');
  try {
    return body(Pointer<Uint8>.fromAddress(address));
  } finally {
    _localFree(address);
  }
}

/// [text] as a NUL-terminated UTF-16 string, for the `W` functions.
T _withString<T>(String text, T Function(Pointer<Uint16> wide) body) =>
    _withMemory((text.length + 1) * 2, (memory) {
      final wide = memory.cast<Uint16>();
      wide.asTypedList(text.length).setAll(0, text.codeUnits);
      return body(wide);
    });

// ---------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------

final _findWindowEx = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, IntPtr, Pointer<Uint16>, Pointer<Uint16>),
      int Function(int, int, Pointer<Uint16>, Pointer<Uint16>)
    >('FindWindowExW');

final _getWindowThreadProcessId = _user32
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId');

final _getCurrentProcessId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');

final _isWindowVisible = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'IsWindowVisible',
    );

final _getWindowLongPtr = _user32
    .lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>(
      'GetWindowLongPtrW',
    );

final _getWindowRect = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('GetWindowRect');

final _getClientRect = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('GetClientRect');

final _clientToScreen = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('ClientToScreen');

final _getLayeredWindowAttributes = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>)
    >('GetLayeredWindowAttributes');

// POINT is two LONGs, which the x64 calling convention passes by value in one
// register — so it is declared as the 64-bit integer it travels as.
final _windowFromPoint = _user32
    .lookupFunction<IntPtr Function(Int64), int Function(int)>(
      'WindowFromPoint',
    );

final _getAncestor = _user32
    .lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>(
      'GetAncestor',
    );

final _getForegroundWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');

final _setForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetForegroundWindow',
    );

final _getSystemMetrics = _user32
    .lookupFunction<Int32 Function(Int32), int Function(int)>(
      'GetSystemMetrics',
    );

final _setCursorPos = _user32
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'SetCursorPos',
    );

final _mouseEvent = _user32
    .lookupFunction<
      Void Function(Uint32, Uint32, Uint32, Uint32, IntPtr),
      void Function(int, int, int, int, int)
    >('mouse_event');

const exLayered = 0x00080000;
const exTopmost = 0x00000008;
const exTransparent = 0x00000020;
const exNoActivate = 0x08000000;
const exToolWindow = 0x00000080;

/// A rectangle on the screen, in physical pixels.
class ScreenRect {
  const ScreenRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;

  bool contains(int x, int y) =>
      x >= left && x < right && y >= top && y < bottom;

  @override
  String toString() => '($left, $top) ${width}x$height';
}

/// The primary monitor, which is where the overlay goes by default.
ScreenRect get primaryMonitor =>
    ScreenRect(0, 0, _getSystemMetrics(0), _getSystemMetrics(1));

/// Top-level windows of [windowClass] that belong to **this** process.
///
/// The process check is not pedantry. An installed copy of the app running on
/// the same desktop has windows of exactly these classes, and a test that
/// found that one's overlay would be asserting about somebody's real call.
List<int> _ownWindows(String windowClass) => _withString(windowClass, (name) {
  final own = _getCurrentProcessId();
  final found = <int>[];
  var window = 0;
  while (true) {
    window = _findWindowEx(0, window, name, nullptr);
    if (window == 0) break;
    final pid = _withMemory(4, (memory) {
      _getWindowThreadProcessId(window, memory.cast<Uint32>());
      return memory.cast<Uint32>().value;
    });
    if (pid == own) found.add(window);
  }
  return found;
});

/// A top-level window, as Windows describes it.
class NativeWindow {
  const NativeWindow(this.handle);

  final int handle;

  bool get isVisible => _isWindowVisible(handle) != 0;

  /// `GWL_EXSTYLE`; test against the `ex*` constants.
  int get exStyle => _getWindowLongPtr(handle, -20);

  bool get isClickThrough => exStyle & exTransparent != 0;
  bool get isTopmost => exStyle & exTopmost != 0;
  bool get isForeground => _getForegroundWindow() == handle;

  void bringToFront() => _setForegroundWindow(handle);

  /// The whole window, frame included.
  ScreenRect get bounds => _withMemory(16, (memory) {
    final rect = memory.cast<Int32>();
    _getWindowRect(handle, rect);
    return ScreenRect(rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1]);
  });

  /// The part the application draws in, in screen coordinates.
  ScreenRect get clientArea => _withMemory(24, (memory) {
    final rect = memory.cast<Int32>();
    _getClientRect(handle, rect);
    final origin = (memory + 16).cast<Int32>();
    _clientToScreen(handle, origin);
    return ScreenRect(origin[0], origin[1], rect[2], rect[3]);
  });

  /// What `SetLayeredWindowAttributes` was last told, read back.
  ///
  /// [colorKey] is 0x00RRGGBB — converted from Windows' own 0x00BBGGRR so it
  /// compares directly against a Dart colour with the alpha masked off.
  ({int colorKey, int alpha, bool keyed, bool faded}) get layered =>
      _withMemory(12, (memory) {
        final key = memory.cast<Uint32>();
        final alpha = (memory + 4).cast<Uint8>();
        final flags = (memory + 8).cast<Uint32>();
        if (_getLayeredWindowAttributes(handle, key, alpha, flags) == 0) {
          throw StateError('The window is not layered, or was never keyed.');
        }
        final bgr = key.value;
        return (
          colorKey:
              ((bgr & 0xFF) << 16) | (bgr & 0xFF00) | ((bgr >> 16) & 0xFF),
          alpha: alpha.value,
          keyed: flags.value & 0x1 != 0,
          faded: flags.value & 0x2 != 0,
        );
      });
}

/// The overlay window of this process, or null before the first `show`.
NativeWindow? get overlayWindow {
  final windows = _ownWindows('HARDLINE_OVERLAY_WINDOW');
  return windows.isEmpty ? null : NativeWindow(windows.first);
}

/// The application's own window — the one the test is running in.
NativeWindow get appWindow =>
    NativeWindow(_ownWindows('FLUTTER_RUNNER_WIN32_WINDOW').first);

/// Whether the window in front belongs to this process.
///
/// Either of its two windows counts: in edit mode the overlay takes the
/// foreground from the application, and that is still this test's desktop.
bool get foregroundIsOurs {
  final foreground = _getForegroundWindow();
  if (foreground == 0) return false;
  final pid = _withMemory(4, (memory) {
    _getWindowThreadProcessId(foreground, memory.cast<Uint32>());
    return memory.cast<Uint32>().value;
  });
  return pid == _getCurrentProcessId();
}

/// The top-level window a click at this point would go to.
///
/// Hit-testing skips a layered window that is also `WS_EX_TRANSPARENT`, so
/// this is how to tell whether clicks fall through the overlay without
/// clicking on anything.
int windowUnder(int x, int y) {
  final hit = _windowFromPoint((y << 32) | (x & 0xFFFFFFFF));
  // GA_ROOT: the Flutter view is a child window, and it is its parent that
  // identifies whose it is.
  return hit == 0 ? 0 : _getAncestor(hit, 2);
}

/// Drags the real mouse from one screen point to another.
///
/// Only ever used over the overlay in edit mode, which covers its monitor with
/// an opaque sheet — so nothing else on the desktop can be under the pointer
/// when the button goes down.
Future<void> dragMouse({
  required int fromX,
  required int fromY,
  required int toX,
  required int toY,
  required Future<void> Function() settle,
}) async {
  const leftDown = 0x0002;
  const leftUp = 0x0004;
  _setCursorPos(fromX, fromY);
  await settle();
  _mouseEvent(leftDown, 0, 0, 0, 0);
  await settle();
  // In steps, because a gesture recogniser needs to see movement to call it a
  // drag — a pointer that teleports is a tap somewhere else.
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    _setCursorPos(
      fromX + (toX - fromX) * i ~/ steps,
      fromY + (toY - fromY) * i ~/ steps,
    );
    await settle();
  }
  _mouseEvent(leftUp, 0, 0, 0, 0);
  await settle();
}

// ---------------------------------------------------------------------------
// Pixels
// ---------------------------------------------------------------------------

final _getDC = _user32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');

final _releaseDC = _user32
    .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
      'ReleaseDC',
    );

final _createCompatibleDC = _gdi32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'CreateCompatibleDC',
    );

final _createCompatibleBitmap = _gdi32
    .lookupFunction<
      IntPtr Function(IntPtr, Int32, Int32),
      int Function(int, int, int)
    >('CreateCompatibleBitmap');

final _selectObject = _gdi32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>(
      'SelectObject',
    );

final _deleteObject = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');

final _deleteDC = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');

final _bitBlt = _gdi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Int32,
        Int32,
        Int32,
        Int32,
        IntPtr,
        Int32,
        Int32,
        Uint32,
      ),
      int Function(int, int, int, int, int, int, int, int, int)
    >('BitBlt');

final _getDIBits = _gdi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        IntPtr,
        Uint32,
        Uint32,
        Pointer<Uint8>,
        Pointer<Uint8>,
        Uint32,
      ),
      int Function(int, int, int, int, Pointer<Uint8>, Pointer<Uint8>, int)
    >('GetDIBits');

/// A piece of the screen as it was composited, layered windows included.
///
/// This is what a screen capture sees, which makes it the right witness twice
/// over: it shows whether the overlay is really see-through, and it honours
/// `WDA_EXCLUDEFROMCAPTURE` — so a window excluded from capture is absent from
/// it exactly as it would be from somebody's screen share.
class ScreenShot {
  ScreenShot._(this.area, this._bgra);

  /// Captures [area] of the desktop.
  factory ScreenShot.of(ScreenRect area) {
    final width = area.width;
    final height = area.height;

    final screen = _getDC(0);
    final memoryDC = _createCompatibleDC(screen);
    final bitmap = _createCompatibleBitmap(screen, width, height);
    final previous = _selectObject(memoryDC, bitmap);
    try {
      // SRCCOPY | CAPTUREBLT. The second is what includes layered windows,
      // and the overlay is one.
      _bitBlt(
        memoryDC,
        0,
        0,
        width,
        height,
        screen,
        area.left,
        area.top,
        0x00CC0020 | 0x40000000,
      );
      _selectObject(memoryDC, previous);

      return _withMemory(40, (header) {
        // BITMAPINFOHEADER. A negative height asks for the rows top-down.
        final fields = header.cast<Int32>();
        fields[0] = 40;
        fields[1] = width;
        fields[2] = -height;
        header.cast<Uint16>()[6] = 1; // biPlanes
        header.cast<Uint16>()[7] = 32; // biBitCount
        return _withMemory(width * height * 4, (pixels) {
          _getDIBits(screen, bitmap, 0, height, pixels, header, 0);
          return ScreenShot._(
            area,
            Uint8List.fromList(pixels.asTypedList(width * height * 4)),
          );
        });
      });
    } finally {
      _deleteObject(bitmap);
      _deleteDC(memoryDC);
      _releaseDC(0, screen);
    }
  }

  final ScreenRect area;
  final Uint8List _bgra;

  /// The colour at a **screen** coordinate, as 0x00RRGGBB.
  int at(int x, int y) {
    final offset = ((y - area.top) * area.width + (x - area.left)) * 4;
    return (_bgra[offset + 2] << 16) | (_bgra[offset + 1] << 8) | _bgra[offset];
  }

  /// How many pixels are exactly [rgb].
  int count(int rgb) => countWhere((pixel) => pixel == (rgb & 0xFFFFFF));

  int countWhere(bool Function(int rgb) test) {
    var matches = 0;
    for (var offset = 0; offset < _bgra.length; offset += 4) {
      final pixel =
          (_bgra[offset + 2] << 16) | (_bgra[offset + 1] << 8) | _bgra[offset];
      if (test(pixel)) matches++;
    }
    return matches;
  }

  /// How many pixels differ from [other], which must cover the same area.
  int differenceFrom(ScreenShot other) {
    var different = 0;
    for (var offset = 0; offset < _bgra.length; offset += 4) {
      if (_bgra[offset] != other._bgra[offset] ||
          _bgra[offset + 1] != other._bgra[offset + 1] ||
          _bgra[offset + 2] != other._bgra[offset + 2]) {
        different++;
      }
    }
    return different;
  }

  /// Writes the capture as a PNG when a directory was asked for.
  ///
  /// Off unless the run passes `--dart-define=HARDLINE_TEST_SHOTS=<dir>`, so an
  /// ordinary run leaves nothing behind. The assertions never depend on it; it
  /// exists so that a failure can be looked at rather than only counted.
  Future<void> save(String name) async {
    const directory = String.fromEnvironment('HARDLINE_TEST_SHOTS');
    if (directory.isEmpty) return;

    final rgba = Uint8List(_bgra.length);
    for (var offset = 0; offset < _bgra.length; offset += 4) {
      rgba[offset] = _bgra[offset + 2];
      rgba[offset + 1] = _bgra[offset + 1];
      rgba[offset + 2] = _bgra[offset];
      rgba[offset + 3] = 0xFF;
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: area.width,
      height: area.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(png!.buffer.asUint8List());
  }
}
