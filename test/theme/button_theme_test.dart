import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/theme/app_theme_state.dart';
import 'package:matrix_client/theme/discord_palettes.dart';
import 'package:matrix_client/theme/discord_spacing.dart';
import 'package:matrix_client/theme/theme_builder.dart';

/// The button theme once set `minimumSize: Size.fromHeight(44)`, which is
/// `Size(double.infinity, 44)` — an infinite *minimum width*.
///
/// That is invisible anywhere a bounded width clamps it, which is every place
/// the app used a button at the time: a `Column(crossAxisAlignment: stretch)`
/// hands down a tight width. It is fatal in a `Row`, which lays out non-flex
/// children with unbounded main-axis constraints. The failure does not look
/// like a button problem either — layout aborts for the entire subtree, so the
/// symptom is a blank screen and a cascade of "render box was not laid out".
void main() {
  final theme = buildThemeData(DiscordPalettes.dark, DiscordMetrics.standard);

  Widget host(Widget child) =>
      MaterialApp(theme: theme, home: Scaffold(body: child));

  group('buttons in unbounded-width slots', () {
    testWidgets('a FilledButton lays out inside a Row', (tester) async {
      await tester.pumpWidget(
        host(
          Row(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Verify')),
              const Spacer(),
              TextButton(onPressed: () {}, child: const Text('Sign out')),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FilledButton)).width,
        lessThan(400),
        reason: 'the button should size to its label, not to infinity',
      );
    });

    testWidgets('a FilledButton lays out in dialog actions', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  content: const Text('body'),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('Cancel')),
                    FilledButton(onPressed: () {}, child: const Text('Apply')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The reason the infinite width went unnoticed: this is what the login
    // screen does, and it still has to produce a full-width button.
    testWidgets('still fills a stretched Column', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Log In')),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(FilledButton)).width, 300);
      // At least the themed height; the measured box also carries the 48px
      // minimum tap target that Material adds around it.
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('tooltip delay', () {
    testWidgets('the theme carries the configured hover delay', (tester) async {
      const delay = Duration(milliseconds: 900);
      final themed = buildThemeData(
        DiscordPalettes.dark,
        DiscordMetrics.standard,
        tooltipDelay: delay,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: themed,
          home: const Scaffold(
            body: Tooltip(message: 'Close settings', child: Icon(Icons.close)),
          ),
        ),
      );

      // Read it the way `Tooltip` does, rather than trusting the field: this is
      // the wiring that makes the settings slider reach every tooltip at once.
      final context = tester.element(find.byType(Tooltip));
      expect(TooltipTheme.of(context).waitDuration, delay);
    });

    testWidgets('defaults to the app default, not Flutter zero', (tester) async {
      final themed = buildThemeData(
        DiscordPalettes.dark,
        DiscordMetrics.standard,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: themed,
          home: const Scaffold(
            body: Tooltip(message: 'x', child: Icon(Icons.close)),
          ),
        ),
      );

      final context = tester.element(find.byType(Tooltip));
      expect(TooltipTheme.of(context).waitDuration, kDefaultTooltipDelay);
      expect(kDefaultTooltipDelay, isNot(Duration.zero));
    });
  });
}
