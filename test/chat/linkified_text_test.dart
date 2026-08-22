// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/chat/widgets/linkified_text.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);
  const style = TextStyle(fontSize: 15);

  Widget host(String text) => ProviderScope(
    child: MaterialApp(
      theme: theme,
      home: Scaffold(body: LinkifiedText(text: text, style: style)),
    ),
  );

  List<InlineSpan> spansOf(WidgetTester tester) =>
      tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!.children!;

  // Selecting and copying a message predates this feature and is the more
  // common thing to want, so a click must not have cost it.
  testWidgets('renders as selectable text', (tester) async {
    await tester.pumpWidget(host('plain words'));

    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('a message with no link is one span and no recognizer', (
    tester,
  ) async {
    await tester.pumpWidget(host('plain words'));

    final spans = spansOf(tester);
    expect(spans.length, 1);
    expect((spans.single as TextSpan).recognizer, isNull);
  });

  testWidgets('a link becomes its own tappable, accented span', (tester) async {
    await tester.pumpWidget(host('see https://example.org for more'));

    final spans = spansOf(tester).cast<TextSpan>();
    expect(spans.map((s) => s.text), [
      'see ',
      'https://example.org',
      ' for more',
    ]);

    expect(spans[0].recognizer, isNull);
    expect(spans[2].recognizer, isNull);

    final link = spans[1];
    expect(link.recognizer, isNotNull);
    expect(link.style?.color, AppPalettes.dark.accent);
    expect(link.style?.decoration, TextDecoration.underline);
    expect(link.mouseCursor, SystemMouseCursors.click);
  });

  // The text the sender wrote must survive the split intact, on screen as well
  // as in the pure function.
  testWidgets('the rendered text still reads as it was sent', (tester) async {
    const body = 'try (https://example.org/a_(b)) today.';
    await tester.pumpWidget(host(body));

    expect(spansOf(tester).map((s) => (s as TextSpan).text).join(), body);
  });

  // Recognizers are disposed with the state; rebuilding on a new message must
  // replace them rather than reuse one that has been torn down.
  testWidgets('swapping the text swaps the spans', (tester) async {
    await tester.pumpWidget(host('https://one.example'));
    final first = (spansOf(tester).single as TextSpan).recognizer;

    await tester.pumpWidget(host('https://two.example'));
    final second = (spansOf(tester).single as TextSpan).recognizer;

    expect((spansOf(tester).single as TextSpan).text, 'https://two.example');
    expect(second, isNot(same(first)));
  });

  // The end of the chain the rest of this file only checks the parts of: a real
  // pointer landing on the glyphs, `RenderEditable` resolving which span was
  // hit, and that span's recognizer firing. Everything else here would still
  // pass if `SelectableText` silently swallowed taps, which is the one failure
  // that would make the whole feature do nothing.
  testWidgets('tapping a link asks before opening it', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(
            // The whole body is the link, so the centre of the widget — where
            // the tap lands — is certain to be inside the link's span.
            body: LinkifiedText(text: 'https://example.org', style: style),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(SelectableText));
    await tester.pumpAndSettle();

    expect(find.text('Open this link?'), findsOneWidget);
    expect(find.text('https://example.org'), findsWidgets);
  });
}
