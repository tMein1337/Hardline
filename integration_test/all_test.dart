// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/overlay/overlay_app.dart';
import 'package:integration_test/integration_test.dart';

import 'hotkeys_flow.dart' as hotkeys;
import 'locked_launch_flow.dart' as locked;
import 'login_flow.dart' as login;
import 'overlay_window_flow.dart' as overlay;
import 'room_admin_flow.dart' as rooms;

/// Every integration suite, in one application.
///
/// Run it with `flutter drive`, not `flutter test`:
///
/// ```powershell
/// flutter drive --driver=test_driver/integration_test.dart `
///   --target=integration_test/all_test.dart -d windows
/// ```
///
/// That is a debug build. The overlay suite is then driven once more on its
/// own with `--profile`, which is an AOT build like the one that ships: the
/// overlay not appearing on the first call after launch only ever happened
/// there, where the second engine starts quickly enough for the app to outrun
/// it. The rest stay in debug, because `flutter_test` cannot type into a
/// profile build — `enterText` arrives empty and a simulated key press is
/// never seen — so they fail there with nothing wrong.
///
/// **Why one file.** On a desktop device the tool builds and launches the
/// application once per test file, and with `flutter test` the second launch
/// fails every time — "The log reader stopped unexpectedly", then "Unable to
/// start the app on the device" — whatever the files contain. Two files that
/// each hold one passing `expect(1, 1)` reproduce it. It is also a third of
/// the wall-clock time: one build and one window rather than one per suite.
///
/// **Why `flutter drive`.** `flutter test` does not compile this file as the
/// program. It generates a bootstrap that imports the test file under a
/// prefix and compiles *that*, so the root library is the bootstrap. The
/// overlay's second engine looks [overlayMain] up by name in the root library
/// — the Windows embedder offers no way to name a different one — finds
/// nothing, and never starts; what is left is the overlay window with no
/// engine behind it, a black sheet over the monitor. `flutter drive` compiles
/// the target itself, so the name resolves exactly as it does in
/// `lib/main.dart`. The overlay suite checks for this and says so rather than
/// failing forty assertions about pixels.
///
/// The price of one process is that the suites share it. Nothing carries over
/// through the widget tree, which each test pumps afresh, but anything taken
/// from the *operating system* does — a registered chord, a window. A suite
/// that takes one gives it back before it finishes, and asserts it did.
///
/// **The overlay suite goes first**, and has to: its opening test is about the
/// first time the overlay is shown in the life of a process, and there is only
/// one of those.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('overlay', overlay.main);
  group('login', login.main);
  group('hotkeys', hotkeys.main);
  group('rooms', rooms.main);
  // Last, because it runs the real `main()`, which puts its own root in the
  // window and builds a client.
  group('locked launch', locked.main);
}

/// The overlay engine's entry point, as `lib/main.dart` declares it.
///
/// Repeated here because the engine resolves it in whichever library holds
/// `main`, and under `flutter drive` that is this one.
@pragma('vm:entry-point')
void overlayMain() => runOverlayApp();
