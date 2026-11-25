// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/markdown_format.dart';
import 'package:hardline/features/chat/matrix_html.dart';
import 'package:hardline/features/chat/mentions.dart';
import 'package:hardline/features/chat/message_content.dart';

const _fan = MentionCandidate(
  userId: '@fan:example.org',
  displayName: 'snake_case_fan',
);

String? md(String text) => markdownToMatrixHtml(text, candidates: [_fan]);

void main() {
  group('markdownToMatrixHtml', () {
    test('plain text stays plain', () {
      expect(md('hello'), isNull);
      expect(md('a & b < c'), isNull);
      // A single line break is a line break, and needs no HTML to say so.
      expect(md('one\ntwo'), isNull);
    });

    test('emphasis, strikethrough and inline code', () {
      expect(
        md('**bold** _it_ ~~gone~~ `code`'),
        '<strong>bold</strong> <em>it</em> <del>gone</del> <code>code</code>',
      );
    });

    test('headings and paragraphs', () {
      expect(md('# Title\ntext'), '<h1>Title</h1><p>text</p>');
      expect(md('one\n\ntwo'), '<p>one</p><p>two</p>');
    });

    test('line breaks inside a paragraph become <br>', () {
      expect(md('**a**\nb'), '<strong>a</strong><br>b');
    });

    test('lists, nested lists and task lists', () {
      expect(
        md('- a\n- b\n  - c'),
        '<ul><li>a</li><li>b<ul><li>c</li></ul></li></ul>',
      );
      expect(
        md('3. three\n4. four'),
        '<ol start="3"><li>three</li><li>four</li></ol>',
      );
      expect(
        md('- [x] done\n- [ ] todo'),
        '<ul><li>☑ done</li><li>☐ todo</li></ul>',
      );
    });

    test('code blocks keep their language and their line breaks', () {
      expect(
        md('```dart\nvoid main() {\n}\n```'),
        '<pre><code class="language-dart">void main() {\n}\n</code></pre>',
      );
    });

    test('quotes and GitHub alerts', () {
      expect(md('> a\n> b'), '<blockquote><p>a<br>b</p></blockquote>');
      expect(
        md('> [!WARNING]\n> careful'),
        '<blockquote><p><strong>Warning</strong></p><p>careful</p></blockquote>',
      );
    });

    test('tables', () {
      expect(
        md('| a | b |\n|---|---|\n| 1 | 2 |'),
        '<table><thead><tr><th>a</th><th>b</th></tr></thead>'
        '<tbody><tr><td>1</td><td>2</td></tr></tbody></table>',
      );
    });

    test('links, autolinks and images that are not on a homeserver', () {
      expect(md('[site](https://x.org)'), '<a href="https://x.org">site</a>');
      expect(
        md('see https://x.org'),
        'see <a href="https://x.org">https://x.org</a>',
      );
      expect(
        md('![cat](https://x.org/c.png)'),
        '<a href="https://x.org/c.png">cat</a>',
      );
      expect(
        md('![emote](mxc://x.org/abc)'),
        '<img src="mxc://x.org/abc" alt="emote">',
      );
    });

    test('rules, footnotes, spoilers and emoji shortcodes', () {
      expect(md('---'), '<hr>');
      expect(md('a[^1]\n\n[^1]: note'), contains('<sup>1</sup>'));
      expect(md('a[^1]\n\n[^1]: note'), isNot(contains('#fn')));
      expect(md('||secret||'), '<span data-mx-spoiler="">secret</span>');
      expect(md(':rocket:'), '🚀');
    });

    test('inline HTML is allowed, but only the Matrix subset', () {
      expect(md('<u>under</u>'), '<u>under</u>');
      expect(md('x<script>alert(1)</script>'), 'x');
      expect(md('<a href="javascript:alert(1)">x</a>'), '<a>x</a>');
    });

    test('mentions become links and survive Markdown', () {
      expect(
        md('hi @snake_case_fan'),
        'hi <a href="https://matrix.to/#/%40fan%3Aexample.org">@snake_case_fan</a>',
      );
      // Inside code a mention is only characters.
      expect(md('`@snake_case_fan`'), '<code>@snake_case_fan</code>');
    });
  });

  group('textMessageContent', () {
    test('sends the Markdown as body and the HTML alongside', () {
      final content = textMessageContent('**hi**');
      expect(content['body'], '**hi**');
      expect(content['format'], 'org.matrix.custom.html');
      expect(content['formatted_body'], '<strong>hi</strong>');
    });

    test('@room is a room mention', () {
      expect(textMessageContent('@room look')['m.mentions'], {'room': true});
      expect(
        textMessageContent('mail@room.org').containsKey('m.mentions'),
        isFalse,
      );
    });
  });

  group('sanitizeMatrixHtml', () {
    String clean(String html) => serializeFragment(parseMatrixHtml(html));

    test('drops the reply fallback and dangerous tags with their content', () {
      expect(
        clean('<mx-reply><blockquote>old</blockquote></mx-reply>new'),
        'new',
      );
      expect(clean('<style>p{}</style><p>x</p>'), '<p>x</p>');
    });

    test('unwraps unknown tags but keeps their text', () {
      expect(clean('<article><b>x</b></article>'), '<b>x</b>');
    });

    test('keeps only allowed attributes', () {
      expect(
        clean('<span data-mx-color="#ff0000" style="x" onclick="y">r</span>'),
        '<span data-mx-color="#ff0000">r</span>',
      );
      expect(clean('<code class="evil">x</code>'), '<code>x</code>');
      expect(
        clean('<code class="language-rust">x</code>'),
        '<code class="language-rust">x</code>',
      );
    });

    test('images only from the homeserver', () {
      expect(clean('<img src="https://tracker.example/p.gif" alt="hi">'), 'hi');
    });
  });
}
