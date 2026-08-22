// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/chat/widgets/link_confirmation.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);
  final url = Uri.parse('https://example.org/a/long/path?q=1');

  /// Pumps a button that asks, and records what the answer was.
  ///
  /// Driving it through a real widget rather than calling the function with a
  /// synthetic context is the point: the dialog is a route, and the caller has
  /// to survive it being pushed and popped.
  Future<List<bool?>> host(WidgetTester tester, SharedPreferences prefs) async {
    final answers = <bool?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async =>
                    answers.add(await confirmOpenLink(context, ref, url)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    return answers;
  }

  testWidgets('asks by default, and shows where the link goes', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final answers = await host(tester, await SharedPreferences.getInstance());

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Open this link?'), findsOneWidget);
    expect(find.text('example.org'), findsOneWidget);
    expect(find.text(url.toString()), findsOneWidget);
    expect(answers, isEmpty);
  });

  testWidgets('cancelling refuses the link', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final answers = await host(tester, await SharedPreferences.getInstance());

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answers, [false]);
  });

  testWidgets('accepting allows the link', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final answers = await host(tester, await SharedPreferences.getInstance());

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();

    expect(answers, [true]);
  });

  testWidgets('turning it off in settings opens without a dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.security_prefs_v1': '{"confirmLinks":false}',
    });
    final answers = await host(tester, await SharedPreferences.getInstance());

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Open this link?'), findsNothing);
    expect(answers, [true]);
  });

  testWidgets('"do not ask again" with Open stops asking and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final answers = await host(tester, prefs);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();

    expect(answers, [true]);
    expect(prefs.getString('security_prefs_v1'), '{"confirmLinks":false}');

    // And the next link goes straight through.
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Open this link?'), findsNothing);
    expect(answers, [true, true]);
  });

  // Ticking the box and then thinking better of the link says something about
  // the link, not about the safeguard.
  testWidgets('"do not ask again" with Cancel changes nothing', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final answers = await host(tester, prefs);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answers, [false]);
    expect(prefs.getString('security_prefs_v1'), isNull);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Open this link?'), findsOneWidget);
  });
}
