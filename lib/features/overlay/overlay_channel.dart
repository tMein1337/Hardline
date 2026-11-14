// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../hotkeys/hotkey.dart';

/// One monitor the overlay could be put on.
@immutable
class OverlayMonitor {
  const OverlayMonitor({
    required this.id,
    required this.label,
    required this.primary,
  });

  /// The Windows device name. Empty means "whichever is primary".
  final String id;
  final String label;
  final bool primary;
}

/// What the runner reports about the application in front.
@immutable
class ForegroundApp {
  const ForegroundApp({required this.executable, required this.title});

  const ForegroundApp.none() : executable = '', title = '';

  /// Lowercased basename, e.g. `javaw.exe`. The key layouts are assigned to.
  final String executable;
  final String title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForegroundApp &&
          executable == other.executable &&
          title == other.title;

  @override
  int get hashCode => Object.hash(executable, title);
}

/// The app side of the overlay's platform channels.
///
/// Everything here is a no-op off Windows, returning the answer that leaves the
/// caller working rather than throwing: the overlay is a Windows feature today,
/// and the settings pane says so instead of offering a switch that does
/// nothing. The same shape the store cipher takes on Nix.
class OverlayChannel {
  OverlayChannel() {
    if (!isSupported) return;
    _events.setMethodCallHandler(_onEvent);
  }

  static const _control = MethodChannel('hardline/overlay');
  static const _events = MethodChannel('hardline/overlay_events');

  /// Windows only, for now. The overlay is a layered, topmost, click-through
  /// window and a second Flutter engine, and both halves are written against
  /// Win32 in `windows/runner/`.
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  final _foreground = StreamController<ForegroundApp>.broadcast();
  final _hotkeys = StreamController<int>.broadcast();
  final _edits = StreamController<String>.broadcast();

  /// Fires when a different *application* comes to the front.
  ///
  /// Already de-duplicated by the runner: alt-tabbing between two windows of
  /// one program is not a layout change, and re-pushing one would restart every
  /// fade on the HUD.
  Stream<ForegroundApp> get foregroundApp => _foreground.stream;

  /// The id of a chord that fired; see [registerHotkey].
  Stream<int> get hotkeys => _hotkeys.stream;

  /// Raw payloads the overlay isolate sent back, for `overlay_wire.dart` to
  /// decode. Kept opaque here so this file knows nothing about the format.
  ///
  /// Named for the first thing that came back over it, a dragged layout. It
  /// also carries the overlay saying it is listening and that it has drawn.
  Stream<String> get edits => _edits.stream;

  Future<void> dispose() async {
    await _foreground.close();
    await _hotkeys.close();
    await _edits.close();
  }

  Future<List<OverlayMonitor>> listMonitors() async {
    if (!isSupported) return const [];
    final raw = await _invoke<List<Object?>>('listMonitors');
    if (raw == null) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          OverlayMonitor(
            id: entry['id'] is String ? entry['id']! as String : '',
            label: entry['label'] is String ? entry['label']! as String : '',
            primary: entry['primary'] is bool
                ? entry['primary']! as bool
                : false,
          ),
    ];
  }

  /// Brings the overlay up, creating its window and engine on the first call.
  ///
  /// [state] is sent with it rather than pushed afterwards: the engine does not
  /// exist until this call returns, so anything pushed before it would have
  /// been dropped and the HUD would come up blank until somebody spoke.
  ///
  /// [opacity] is what the window is shown *at*, 0..255, applied before it
  /// becomes visible. The controller passes zero and raises it once the
  /// overlay has drawn [state]; see `OverlayDrawn`.
  Future<bool> show({
    required String monitorId,
    required bool clickThrough,
    required bool excludeFromCapture,
    required int opacity,
    required String state,
  }) async {
    if (!isSupported) return false;
    try {
      await _control.invokeMethod<void>('show', {
        'monitor': monitorId,
        'clickThrough': clickThrough,
        'excludeFromCapture': excludeFromCapture,
        'opacity': opacity.clamp(0, 255),
        'state': state,
      });
      return true;
    } on PlatformException catch (error) {
      // The window or its engine would not start. The overlay is then simply
      // unavailable; nothing else in the app depends on it. The message names
      // the step that failed — see `OverlayWindow::Create`.
      debugPrint('[overlay] could not show: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> hide() => _invoke<void>('hide');

  Future<void> setClickThrough(bool value) =>
      _invoke<void>('setClickThrough', {'value': value});

  /// Which colour the runner turns into a hole.
  ///
  /// Must be sent **before** the HUD paints with it. The two sides agreeing is
  /// what makes the overlay transparent at all; while they disagree nothing is
  /// keyed and the plate sits opaque over the game.
  Future<void> setChromaKey(int argb) =>
      _invoke<void>('setChromaKey', {'value': argb});

  /// How opaque everything the HUD paints is, 0..255.
  ///
  /// The colour-keyed holes stay holes at any value — see `kChromaKey`. This
  /// is the overlay's fade, moved from the widgets to the window because a
  /// layered window has no per-pixel alpha to give them.
  Future<void> setOpacity(int alpha) =>
      _invoke<void>('setOpacity', {'value': alpha.clamp(0, 255)});

  Future<void> setMonitor(String id) => _invoke<void>('setMonitor', {'id': id});

  Future<void> setCaptureExclusion(bool value) =>
      _invoke<void>('setCaptureExclusion', {'value': value});

  Future<void> pushState(String state) =>
      _invoke<void>('pushState', {'state': state});

  /// Binds a global chord, replacing whatever [id] was bound to before.
  ///
  /// Returns false when Windows refused it, which almost always means another
  /// program holds it — that is a fact worth telling the user rather than a
  /// failure to retry.
  Future<bool> registerHotkey(int id, Hotkey hotkey) async {
    if (!isSupported || !hotkey.isBound) {
      await unregisterHotkey(id);
      return false;
    }
    final ok = await _invoke<bool>('registerHotkey', {
      'id': id,
      'modifiers': hotkey.modifiers,
      'key': hotkey.key,
    });
    return ok ?? false;
  }

  Future<void> unregisterHotkey(int id) =>
      _invoke<void>('unregisterHotkey', {'id': id});

  /// Asks once, for the case where the overlay is switched on while a game is
  /// already in front and no foreground event is coming.
  Future<ForegroundApp> currentForegroundApp() async {
    final raw = await _invoke<Map<Object?, Object?>>('foregroundApp');
    if (raw == null) return const ForegroundApp.none();
    return ForegroundApp(
      executable: raw['executable'] is String
          ? raw['executable']! as String
          : '',
      title: raw['title'] is String ? raw['title']! as String : '',
    );
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!isSupported) return null;
    try {
      return await _control.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('[overlay] $method failed: ${error.message}');
      return null;
    } on MissingPluginException {
      // A build without the runner change, or a widget test. Neither is worth
      // an exception escaping into the call path.
      return null;
    }
  }

  Future<Object?> _onEvent(MethodCall call) async {
    switch (call.method) {
      case 'foregroundApp':
        final args = call.arguments;
        if (args is Map) {
          _foreground.add(
            ForegroundApp(
              executable: args['executable'] is String
                  ? args['executable']! as String
                  : '',
              title: args['title'] is String ? args['title']! as String : '',
            ),
          );
        }
      case 'hotkey':
        if (call.arguments is int) _hotkeys.add(call.arguments as int);
      case 'overlayEvent':
        if (call.arguments is String) _edits.add(call.arguments as String);
    }
    return null;
  }
}
