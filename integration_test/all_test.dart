// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'hotkeys_flow.dart' as hotkeys;
import 'login_flow.dart' as login;

/// The one file `flutter test integration_test -d windows` finds.
///
/// **Every suite is run from here, and none of them is named `*_test.dart`.**
/// That is not a preference. On a desktop device `flutter test` builds and
/// launches the application once per test file, and the second launch fails
/// every time — "The log reader stopped unexpectedly", then "Unable to start
/// the app on the device" — whatever the files contain. Two files that each
/// hold one passing `expect(1, 1)` reproduce it. So there can only be one
/// file for the tool to discover, and it has to pull the rest in.
///
/// It is also a third of the wall-clock time: one build and one window rather
/// than one of each per suite.
///
/// The price is that the suites share a process. Nothing carries over between
/// them through the widget tree, which each test pumps afresh, but anything
/// taken from the *operating system* does — a registered chord, a window. A
/// suite that takes one gives it back before it finishes, and asserts it did.
///
/// A suite still runs on its own, which is what to do while writing one:
///
/// ```powershell
/// flutter test integration_test/hotkeys_flow.dart -d windows
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('login', login.main);
  group('hotkeys', hotkeys.main);
}
