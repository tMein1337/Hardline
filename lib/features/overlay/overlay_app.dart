// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'overlay_layout.dart';
import 'overlay_wire.dart';
import 'widgets/overlay_hud.dart';

/// The channel this isolate shares with the runner, and through it the app.
const _channel = MethodChannel('hardline/overlay_state');

/// What to key on before any palette has arrived.
///
/// Matches `kDefaultChromaKey` in `overlay_window.h`. Once a snapshot lands,
/// the key comes from the palette instead — see `OverlayPalette.chromaKey`,
/// which derives it from the plate so the antialiased edges are invisible in
/// any theme.
///
/// It only matches the *window* when the theme is the shipped dark one, and
/// the window is keyed on the real palette before it is ever shown. So in any
/// other theme a frame painted with this is an opaque sheet over the monitor.
/// That frame is never seen: the app holds the window at zero opacity until
/// [OverlayDrawn] tells it a real snapshot is on screen.
const kDefaultChromaKey = Color(0xFF09090B);

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

  // Listening before `runApp`, not from a widget's `initState`, and the order
  // is the fix for the overlay staying empty through the first call after
  // launch.
  //
  // `runApp` only *schedules* the first build. A handler installed by a widget
  // therefore goes in a turn of the event loop after this function returns —
  // and the app has usually sent two messages by then, the snapshot that came
  // with `show` and the speaking update that follows it. A channel nobody is
  // listening to keeps one message. The speaking update pushed the snapshot
  // out, and the HUD drew an empty roster until the roster next changed, which
  // in a call of the same people is never.
  //
  // Nothing can arrive before this line: the engine delivers messages on the
  // thread that is running it.
  final model = OverlayModel(
    send: (payload) => _channel.invokeMethod<void>('event', payload),
  );
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'state') model.receive(call.arguments as String?);
    return null;
  });
  model.announce();

  runApp(OverlayRoot(model: model));
}

/// Everything the overlay isolate knows, and the two things it says back.
///
/// Separate from the widget so that it can exist before the first build —
/// see [runOverlayApp] — and so the conversation with the app can be tested
/// without a second engine to have it in.
class OverlayModel extends ChangeNotifier {
  OverlayModel({required this.send});

  /// Hands a message to the app. Failures are the caller's to ignore: there
  /// is nobody in this isolate to report them to.
  final Future<void> Function(String payload) send;

  /// Nothing until the first push. The window is not given any opacity until
  /// one has been drawn, so this gap is never on screen.
  OverlaySnapshot? get snapshot => _snapshot;
  OverlaySnapshot? _snapshot;

  Set<String> get speaking => _speaking;
  Set<String> _speaking = const {};

  /// The layout as the user is dragging it, before the app has written it back.
  ///
  /// Held locally so a drag follows the mouse at frame rate: the round trip out
  /// to the app, into preferences and back would put the HUD a couple of frames
  /// behind the pointer, which feels like the drag is slipping.
  OverlayLayout? get dragging => _dragging;
  OverlayLayout? _dragging;

  /// Serials of snapshots applied but not yet confirmed as drawn.
  final List<int> _undrawn = [];

  /// Tells the app this isolate is listening; see [OverlayReady].
  void announce() => _send(const OverlayReady().encode());

  /// Takes one message from the app.
  void receive(String? payload) {
    final message = decodeOverlayMessage(payload);

    if (message is OverlaySnapshot) {
      _snapshot = message;
      // The app has caught up with the drag, or edit mode ended. Either way
      // the local copy has stopped being the newer one.
      _dragging = null;
      _undrawn.add(overlaySerialOf(payload));
      notifyListeners();
      _confirmAfterFrame();
    } else if (message is OverlaySpeaking) {
      // The hot path. A set of ids, several times a second, and nothing else —
      // avatars are kilobytes and do not belong in a message sent at that rate.
      if (setEquals(_speaking, message.userIds)) return;
      _speaking = message.userIds;
      notifyListeners();
    }
  }

  /// Reports each applied snapshot once the frame that shows it is finished.
  ///
  /// After the frame rather than on receipt: the app is waiting to make the
  /// window visible, and "I have the data" is not "it is on the screen". A
  /// snapshot confirmed too early is the previous call's roster flashing up
  /// for a frame before the new one replaces it.
  void _confirmAfterFrame() {
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) {
      final drawn = List.of(_undrawn);
      _undrawn.clear();
      for (final serial in drawn) {
        _send(OverlayDrawn(serial).encode());
      }
    });
    // A post-frame callback does not ask for a frame, and a snapshot equal to
    // the last one would not have dirtied anything.
    binding.scheduleFrame();
  }

  void drag(double x, double y) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    _dragging = (_dragging ?? snapshot.layout).copyWith(x: x, y: y);
    notifyListeners();
  }

  /// Sends the finished position back for the app to persist.
  ///
  /// On drag end rather than continuously, for the reason the volume sliders
  /// commit on release: a gesture emits changes far faster than a write is
  /// worth, and only the last one is a decision.
  void commitDrag() {
    final layout = _dragging;
    if (layout == null) return;
    _send(OverlayEdit(layout).encode());
  }

  void _send(String payload) => unawaited(
    send(payload).catchError((Object error) {
      // The runner is not there to hear it: a widget test, or the window
      // being torn down. Nothing useful can be done from this side.
    }),
  );
}

/// The overlay's root widget: the colour key, and the HUD on top of it.
class OverlayRoot extends StatelessWidget {
  const OverlayRoot({super.key, required this.model});

  final OverlayModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final snapshot = model.snapshot;
        final dragging = model.dragging;

        // What the window is currently keying on: the palette's once one has
        // arrived, and the compiled-in default until then.
        final chromaKey = snapshot == null
            ? kDefaultChromaKey
            : Color(snapshot.palette.chromaKey);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          // Painted, not left transparent — which is the opposite of what this
          // used to do, and the correction is the whole of the overlay bug.
          //
          // A Flutter view on Windows is a child HWND that the engine renders
          // opaque. There is no clear colour, no background colour and no
          // alpha mode in `flutter_windows.h`, so "paint nothing and let the
          // window be transparent" cannot work: the engine still fills the
          // surface, and the monitor ends up solid in the engine's default
          // clear colour. Which is exactly what was reported — a screen of
          // white.
          //
          // So the runner keys on a colour instead, and this is where that
          // colour is put on screen. Every pixel of it becomes a hole through
          // to the game; everything the HUD draws on top of it stays.
          //
          // The colour follows the palette — see `OverlayPalette.chromaKey` —
          // so it must be whatever the runner was last told, and the
          // controller sends that before pushing the palette that carries it.
          // **A mismatch is an opaque rectangle over somebody's game**, so the
          // order matters more than the value does.
          color: chromaKey,
          // A `Material`, and not merely a `Container` painting the key.
          //
          // Losing it was how the HUD ended up drawn in yellow with a double
          // underline: that is Flutter's "no `DefaultTextStyle` here" marker,
          // and every `Text` gets it when nothing above supplies a text style.
          // The `Material` is what supplies one — this used to be a
          // `MaterialType.transparency` and painted nothing, which was correct
          // then and is exactly wrong now, since the key has to be painted.
          home: Material(
            color: chromaKey,
            child: snapshot == null
                ? const SizedBox.shrink()
                : OverlayHud(
                    snapshot: dragging == null
                        ? snapshot
                        : OverlaySnapshot(
                            people: snapshot.people,
                            layout: dragging,
                            palette: snapshot.palette,
                            editing: snapshot.editing,
                          ),
                    speaking: model.speaking,
                    onDrag: snapshot.editing ? model.drag : null,
                    onDragEnd: snapshot.editing ? model.commitDrag : null,
                  ),
          ),
        );
      },
    );
  }
}
