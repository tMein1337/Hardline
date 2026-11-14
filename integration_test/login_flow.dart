// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

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
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A login controller that records what the form submitted instead of talking
/// to a homeserver. The screen, its text fields and its button are the real
/// ones, running in a real Windows window — that is the point of this file.
class _RecordingLoginController extends LoginController {
  _RecordingLoginController(this.calls);

  final List<({String homeserver, String username, String password})> calls;

  @override
  LoginFormState build() => const LoginFormState();

  @override
  Future<bool> signIn({
    required String homeserver,
    required String username,
    required String password,
    Client? target,
  }) async {
    calls.add((homeserver: homeserver, username: username, password: password));
    return false;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);

  testWidgets('filling in the form and tapping Log In submits what was typed', (
    tester,
  ) async {
    // Mocked, so this run never reads or writes the developer's real
    // preferences or account list.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final calls = <({String homeserver, String username, String password})>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          encryptionAvailableProvider.overrideWithValue(true),
          loginControllerProvider.overrideWith(
            () => _RecordingLoginController(calls),
          ),
        ],
        child: MaterialApp(theme: theme, home: const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Order on screen: Homeserver, Username, Password.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'matrix.example');
    await tester.enterText(fields.at(1), 'alice');
    await tester.enterText(fields.at(2), 'correct horse');

    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.homeserver, 'matrix.example');
    expect(calls.single.username, 'alice');
    expect(calls.single.password, 'correct horse');
  });
}
