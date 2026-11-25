// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/chat/widgets/formatted_body.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);
  const style = TextStyle(fontSize: 15);

  Future<void> pump(
    WidgetTester tester,
    String html, {
    Map<String, String> mentions = const {},
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: FormattedBody(html: html, style: style, mentions: mentions),
          ),
        ),
      ),
    );
  }

  /// Everything drawn as text, in order — the plain text of every `Text`.
  String drawn(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.textSpan?.toPlainText() ?? t.data ?? '')
      .join('|');

  TextSpan? spanWith(WidgetTester tester, String text) {
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      TextSpan? found;
      widget.textSpan?.visitChildren((span) {
        if (span is TextSpan && span.text == text) {
          found = span;
          return false;
        }
        return true;
      });
      if (found != null) return found;
    }
    return null;
  }

  testWidgets('styles inline formatting', (tester) async {
    await pump(
      tester,
      '<strong>b</strong> <em>i</em> <del>s</del> <code>c</code>',
    );

    expect(spanWith(tester, 'b')!.style!.fontWeight, FontWeight.w700);
    expect(spanWith(tester, 'i')!.style!.fontStyle, FontStyle.italic);
    expect(
      spanWith(tester, 's')!.style!.decoration,
      TextDecoration.lineThrough,
    );
    expect(spanWith(tester, 'c')!.style!.fontFamily, isNotNull);
  });

  testWidgets('draws lists with their markers, and numbered from start', (
    tester,
  ) async {
    await pump(tester, '<ul><li>one</li></ul><ol start="4"><li>four</li></ol>');

    expect(drawn(tester), contains('•|one'));
    expect(drawn(tester), contains('4.|four'));
  });

  testWidgets('draws headings, quotes, code blocks, rules and tables', (
    tester,
  ) async {
    await pump(
      tester,
      '<h1>Title</h1><blockquote>quoted</blockquote>'
      '<pre><code>line 1\nline 2</code></pre><hr>'
      '<table><tr><th>h</th></tr><tr><td>cell</td></tr></table>',
    );

    expect(find.text('line 1\nline 2'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(drawn(tester), contains('Title'));
    expect(drawn(tester), contains('quoted'));
    expect(drawn(tester), contains('cell'));
  });

  testWidgets('a mention shows the name this client knows', (tester) async {
    await pump(
      tester,
      '<a href="https://matrix.to/#/@alice:example.org">@ally</a> hi',
      mentions: {'@alice:example.org': 'Alice'},
    );

    expect(spanWith(tester, '@Alice'), isNotNull);
  });

  testWidgets('a spoiler is hidden until clicked', (tester) async {
    await pump(tester, 'a <span data-mx-spoiler="">secret</span>');

    final hidden = spanWith(tester, 'secret')!;
    expect(hidden.style!.color, hidden.style!.backgroundColor);

    (hidden.recognizer! as dynamic).onTap();
    await tester.pump();

    final shown = spanWith(tester, 'secret')!;
    expect(shown.style!.color, isNot(shown.style!.backgroundColor));
  });

  testWidgets('a link that says one thing asks before going anywhere', (
    tester,
  ) async {
    await pump(
      tester,
      '<a href="https://evil.example">https://bank.example</a>',
    );

    final link = spanWith(tester, 'https://bank.example')!;
    (link.recognizer! as dynamic).onTap();
    await tester.pumpAndSettle();

    expect(find.text('Open this link?'), findsOneWidget);
    expect(find.textContaining('evil.example'), findsWidgets);
  });

  testWidgets('a script never shows up', (tester) async {
    await pump(tester, 'ok<script>alert(1)</script>');

    expect(drawn(tester), isNot(contains('alert')));
  });
}
