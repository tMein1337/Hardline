// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/message_links.dart';

/// The body a caller would get back by pasting every run together again.
String reassemble(List<BodySpan> spans) => spans.map((s) => s.text).join();

void main() {
  group('splitBodyLinks', () {
    test('leaves a message with no link as one plain run', () {
      final spans = splitBodyLinks('no links here, just words');

      expect(spans, [const BodySpan.text('no links here, just words')]);
    });

    test('an empty body has no runs at all', () {
      expect(splitBodyLinks(''), isEmpty);
    });

    test('splits text around a link', () {
      final spans = splitBodyLinks('see https://example.org for more');

      expect(spans.length, 3);
      expect(spans[0].text, 'see ');
      expect(spans[1].isLink, isTrue);
      expect(spans[1].text, 'https://example.org');
      expect(spans[1].target, Uri.parse('https://example.org'));
      expect(spans[2].text, ' for more');
    });

    test('finds every link in one message', () {
      final spans = splitBodyLinks(
        'http://a.example and https://b.example and http://c.example',
      );

      expect(spans.where((s) => s.isLink).map((s) => s.text), [
        'http://a.example',
        'https://b.example',
        'http://c.example',
      ]);
    });

    test('a link can be the whole message', () {
      final spans = splitBodyLinks('https://example.org/x');

      expect(spans.length, 1);
      expect(spans.single.isLink, isTrue);
    });

    // The reason this is a pure function: whatever it decides, the message on
    // screen must still read exactly as it was sent.
    test('never alters the body, only divides it', () {
      const bodies = [
        'plain',
        'see https://example.org.',
        '(https://example.org) and <http://b.example>',
        'https://example.org/a(b)c, then more',
        'trailing space https://example.org ',
        'multi\nline https://example.org\nafter',
      ];

      for (final body in bodies) {
        expect(reassemble(splitBodyLinks(body)), body, reason: body);
      }
    });
  });

  group('splitBodyLinks trims what ends a sentence, not what ends a URL', () {
    String linkIn(String body) =>
        splitBodyLinks(body).firstWhere((s) => s.isLink).text;

    test('a full stop after a link is punctuation', () {
      expect(linkIn('go to https://example.org.'), 'https://example.org');
    });

    test('so are a comma, a colon and a question mark', () {
      expect(linkIn('https://example.org, then'), 'https://example.org');
      expect(linkIn('https://example.org: look'), 'https://example.org');
      expect(linkIn('https://example.org?'), 'https://example.org');
    });

    test('a quoted link keeps neither quote', () {
      expect(linkIn('"https://example.org"'), 'https://example.org');
    });

    test('a bracketed link keeps neither bracket', () {
      expect(linkIn('(see https://example.org)'), 'https://example.org');
      expect(linkIn('<https://example.org>'), 'https://example.org');
    });

    // The case a naive strip gets wrong, and the reason for counting instead.
    test('balanced brackets inside a URL are part of it', () {
      expect(
        linkIn('https://en.example.org/wiki/Thing_(disambiguation)'),
        'https://en.example.org/wiki/Thing_(disambiguation)',
      );
      expect(
        linkIn('(https://en.example.org/wiki/Thing_(disambiguation))'),
        'https://en.example.org/wiki/Thing_(disambiguation)',
      );
    });

    test('a trailing slash is part of the URL', () {
      expect(linkIn('https://example.org/'), 'https://example.org/');
    });

    test('a query string survives', () {
      expect(
        linkIn('https://example.org/s?q=a&b=c'),
        'https://example.org/s?q=a&b=c',
      );
    });
  });

  group('splitBodyLinks refuses what is not addressable', () {
    test('a scheme with no host is not a link', () {
      expect(splitBodyLinks('https:// is a scheme'), [
        const BodySpan.text('https:// is a scheme'),
      ]);
    });

    test('a scheme glued to the end of a word is not a link', () {
      final spans = splitBodyLinks('notahttps://example.org');

      expect(spans.any((s) => s.isLink), isFalse);
    });

    // Deliberate: giving these a scheme would make the label differ from the
    // target, which is the property that lets a link open without a prompt.
    test('a bare host and other schemes are left as text', () {
      for (final body in [
        'www.example.org',
        'mailto:someone@example.org',
        'matrix:r/room:example.org',
        'ftp://example.org',
      ]) {
        expect(
          splitBodyLinks(body).any((s) => s.isLink),
          isFalse,
          reason: body,
        );
      }
    });
  });

  group('parseMatrixTo', () {
    test('an ordinary web address is not a matrix.to link', () {
      expect(parseMatrixTo(Uri.parse('https://example.org/#/!a:b')), isNull);
    });

    test('reads a room id', () {
      final target = parseMatrixTo(
        Uri.parse('https://matrix.to/#/%21abc%3Aexample.org'),
      );

      expect(target?.identifier, '!abc:example.org');
      expect(target?.eventId, isNull);
    });

    test('reads an unencoded room id too', () {
      final target = parseMatrixTo(
        Uri.parse('https://matrix.to/#/!abc:example.org'),
      );

      expect(target?.identifier, '!abc:example.org');
    });

    test('reads an alias', () {
      final target = parseMatrixTo(
        Uri.parse('https://matrix.to/#/%23room%3Aexample.org'),
      );

      expect(target?.identifier, '#room:example.org');
    });

    test('reads a user', () {
      final target = parseMatrixTo(
        Uri.parse('https://matrix.to/#/@alice:example.org'),
      );

      expect(target?.identifier, '@alice:example.org');
    });

    test('reads the event of a message permalink', () {
      final target = parseMatrixTo(
        Uri.parse('https://matrix.to/#/%21abc%3Aexample.org/%24event123'),
      );

      expect(target?.identifier, '!abc:example.org');
      expect(target?.eventId, r'$event123');
    });

    // `via` hangs off the fragment rather than being the URL's own query,
    // because the whole payload is in the fragment — which is what lets
    // matrix.to work as a static page.
    test('ignores the via hint', () {
      final target = parseMatrixTo(
        Uri.parse(
          'https://matrix.to/#/%21abc%3Aexample.org/%24e?via=example.org',
        ),
      );

      expect(target?.identifier, '!abc:example.org');
      expect(target?.eventId, r'$e');
    });

    test('a second part that is not an event id is not read as one', () {
      final target = parseMatrixTo(
        Uri.parse('https://matrix.to/#/%21abc%3Aexample.org/nonsense'),
      );

      expect(target?.eventId, isNull);
    });

    test('an identifier with no sigil is not a Matrix identifier', () {
      expect(parseMatrixTo(Uri.parse('https://matrix.to/#/about')), isNull);
    });

    test('matrix.to with nothing after the hash is not a target', () {
      expect(parseMatrixTo(Uri.parse('https://matrix.to/')), isNull);
      expect(parseMatrixTo(Uri.parse('https://matrix.to/#/')), isNull);
    });
  });
}
