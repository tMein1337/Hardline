// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/accounts/active_client.dart';
import 'package:hardline/features/auth/login_controller.dart';
import 'package:hardline/features/auth/login_form_state.dart';
import 'package:hardline/features/auth/login_screen.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A `signIn` whose completion this test controls.
///
/// The real one cannot be used here — it needs a homeserver — but the timing it
/// has is the whole point of the test, so the fake reproduces it exactly:
/// `state` goes busy immediately, and the future settles only when the test
/// says so, which stands in for `Client.init()` finishing its first sync long
/// after it emitted `LoginState.loggedIn`.
class _SlowLoginController extends LoginController {
  _SlowLoginController(this.result);

  final Future<bool> result;

  @override
  LoginFormState build() => const LoginFormState();

  @override
  Future<bool> signIn({
    required String homeserver,
    required String username,
    required String password,
    Client? target,
  }) {
    state = const LoginFormState(busy: true);
    return result;
  }
}

void main() {
  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);

  // The router replaces this screen with the shell the moment the SDK emits
  // `loggedIn`, which `Client.init()` does *before* `login()` returns — it
  // still has a first sync to wait for. So `_submit` reliably resumes on a
  // widget that is already unmounted, and every `ref` it touches after the
  // await throws "the widget is about to or has been unmounted". Nothing
  // awaits `_submit`, so that arrives as an unhandled exception on the first
  // launch of a fresh install, which is where this was found.
  testWidgets('completing a sign-in after the screen is gone does not throw', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final signedIn = Completer<bool>();
    final showLogin = ValueNotifier<bool>(true);
    addTearDown(showLogin.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          encryptionAvailableProvider.overrideWithValue(true),
          loginControllerProvider.overrideWith(
            () => _SlowLoginController(signedIn.future),
          ),
        ],
        child: MaterialApp(
          theme: theme,
          home: ValueListenableBuilder<bool>(
            valueListenable: showLogin,
            builder: (_, visible, _) => visible
                ? const LoginScreen()
                : const Scaffold(body: Text('shell')),
          ),
        ),
      ),
    );

    // Non-empty, because remembering the homeserver is what reaches for
    // preferences after the await.
    await tester.enterText(find.byType(TextField).first, 'matrix.example');
    await tester.tap(find.text('Log In'));
    await tester.pump();

    // What the router does while the login request is still in flight.
    showLogin.value = false;
    await tester.pump();
    expect(find.text('shell'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    signedIn.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(prefs.getString('last_homeserver'), 'matrix.example');
  });
}
