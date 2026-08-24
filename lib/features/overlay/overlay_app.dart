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

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Transparent from the root down. Anything that painted a background —
      // a `Scaffold`, `MaterialApp`'s own colour — would fill the monitor with
      // an opaque rectangle over the game, which is the one thing this window
      // must never do.
      color: const Color(0x00000000),
      home: Material(
        type: MaterialType.transparency,
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
