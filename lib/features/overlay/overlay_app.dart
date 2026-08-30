// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'overlay_layout.dart';
import 'overlay_wire.dart';
import 'widgets/overlay_hud.dart';

/// The channel this isolate shares with the runner, and through it the app.
const _channel = MethodChannel('hardline/overlay_state');

/// The overlay engine's entry point.
///
/// Called from `overlayMain` in `lib/main.dart`, which is where the engine
/// looks an entry point up — by name, in the library that holds `main`.
///
/// **This is a second isolate.** Nothing from the app is reachable: no
/// `ProviderScope`, no Matrix client, no theme, no `SharedPreferences`. It has
/// exactly one input, the state pushed over [_channel], and that is deliberate
/// rather than a limitation to work around — a second engine that opened the
/// same database or registered flutter_webrtc a second time would break the
/// app it is meant to be reporting on.
/// What to key on before any palette has arrived.
///
/// Matches `kDefaultChromaKey` in `overlay_window.h`, so the very first frame
/// of a freshly created window is keyed correctly. Once a snapshot lands, the
/// key comes from the palette instead — see `OverlayPalette.chromaKey`, which
/// derives it from the plate so the antialiased edges are invisible in any
/// theme.
const kDefaultChromaKey = Color(0xFF09090B);

void runOverlayApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayRoot());
}

class _OverlayRoot extends StatefulWidget {
  const _OverlayRoot();

  @override
  State<_OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<_OverlayRoot> {
  /// Nothing until the first push. The window is only ever shown with a state
  /// attached, so this is the gap between the engine starting and that arriving
  /// — measured in frames, and transparent throughout.
  OverlaySnapshot? _snapshot;
  Set<String> _speaking = const {};

  /// The layout as the user is dragging it, before the app has written it back.
  ///
  /// Held locally so a drag follows the mouse at frame rate: the round trip out
  /// to the app, into preferences and back would put the HUD a couple of frames
  /// behind the pointer, which feels like the drag is slipping.
  OverlayLayout? _dragging;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onCall);
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'state') return null;
    final message = decodeOverlayMessage(call.arguments as String?);

    if (message is OverlaySnapshot) {
      setState(() {
        _snapshot = message;
        // The app has caught up with the drag, or edit mode ended. Either way
        // the local copy has stopped being the newer one.
        _dragging = null;
      });
    } else if (message is OverlaySpeaking) {
      // The hot path. A set of ids, several times a second, and nothing else —
      // avatars are kilobytes and do not belong in a message sent at that rate.
      setState(() => _speaking = message.userIds);
    }
    return null;
  }

  void _onDrag(double x, double y) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    setState(
      () => _dragging = (_dragging ?? snapshot.layout).copyWith(x: x, y: y),
    );
  }

  /// Sends the finished position back for the app to persist.
  ///
  /// On drag end rather than continuously, for the reason the volume sliders
  /// commit on release: a gesture emits changes far faster than a write is
  /// worth, and only the last one is a decision.
  void _commitDrag() {
    final layout = _dragging;
    if (layout == null) return;
    _channel.invokeMethod<void>('event', OverlayEdit(layout).encode());
  }

  /// What the window is currently keying on.
  ///
  /// The palette's until one arrives, then the compiled-in default — which is
  /// what the runner also starts with, so the two agree from the first frame.
  Color get chromaKey => _snapshot == null
      ? kDefaultChromaKey
      : Color(_snapshot!.palette.chromaKey);

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Painted, not left transparent — which is the opposite of what this
      // used to do, and the correction is the whole of the overlay bug.
      //
      // A Flutter view on Windows is a child HWND that the engine renders
      // opaque. There is no clear colour, no background colour and no alpha
      // mode in `flutter_windows.h`, so "paint nothing and let the window be
      // transparent" cannot work: the engine still fills the surface, and the
      // monitor ends up solid in the engine's default clear colour. Which is
      // exactly what was reported — a screen of white.
      //
      // So the runner keys on a colour instead, and this is where that colour
      // is put on screen. Every pixel of it becomes a hole through to the
      // game; everything the HUD draws on top of it stays.
      //
      // The colour follows the palette — see `OverlayPalette.chromaKey` — so
      // it must be whatever the runner was last told, and the controller
      // sends that before pushing the palette that carries it. **A mismatch
      // is an opaque rectangle over somebody's game**, so the order matters
      // more than the value does.
      color: chromaKey,
      // A `Material`, and not merely a `Container` painting the key.
      //
      // Losing it was how the HUD ended up drawn in yellow with a double
      // underline: that is Flutter's "no `DefaultTextStyle` here" marker, and
      // every `Text` gets it when nothing above supplies a text style. The
      // `Material` is what supplies one — this used to be a
      // `MaterialType.transparency` and painted nothing, which was correct
      // then and is exactly wrong now, since the key has to be painted.
      home: Material(
        color: chromaKey,
        child: snapshot == null
            ? const SizedBox.shrink()
            : OverlayHud(
                snapshot: _dragging == null
                    ? snapshot
                    : OverlaySnapshot(
                        people: snapshot.people,
                        layout: _dragging!,
                        palette: snapshot.palette,
                        editing: snapshot.editing,
                      ),
                speaking: _speaking,
                onDrag: snapshot.editing ? _onDrag : null,
                onDragEnd: snapshot.editing ? _commitDrag : null,
              ),
      ),
    );
  }
}
