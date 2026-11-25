// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the composer's text becomes on the wire: Markdown in, Matrix HTML out.
//
// The whole of GitHub-flavoured Markdown — headings, emphasis, strikethrough,
// inline code and fenced blocks with a language, quotes, ordered, unordered
// and task lists, tables, links, autolinks, images, rules, footnotes and
// GitHub's alert blocks — plus inline HTML, `:shortcode:` emoji and
// `||spoilers||`, which Element and most other clients send too.
//
// The body stays the text as typed. That is what clients without HTML show,
// and what this client loads back into the composer to edit.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import 'matrix_html.dart';
import 'mentions.dart';

/// `||hidden||` → `<span data-mx-spoiler>hidden</span>`.
class _SpoilerSyntax extends md.DelimiterSyntax {
  _SpoilerSyntax()
    : super(
        r'\|\|',
        requiresDelimiterRun: true,
        allowIntraWord: true,
        tags: [md.DelimiterTag('span', 2)],
      );

  @override
  Iterable<md.Node>? close(
    md.InlineParser parser,
    md.Delimiter opener,
    md.Delimiter closer, {
    required String tag,
    required List<md.Node> Function() getChildren,
  }) => [md.Element('span', getChildren())..attributes['data-mx-spoiler'] = ''];
}

final _extensions = md.ExtensionSet(
  const [
    md.FencedCodeBlockSyntax(),
    md.TableSyntax(),
    md.UnorderedListWithCheckboxSyntax(),
    md.OrderedListWithCheckboxSyntax(),
    md.FootnoteDefSyntax(),
    md.AlertBlockSyntax(),
  ],
  [
    md.InlineHtmlSyntax(),
    md.StrikethroughSyntax(),
    md.EmojiSyntax(),
    md.AutolinkExtensionSyntax(),
  ],
);

/// Private-use characters around a mention's index while Markdown runs, so a
/// name like `@snake_case_fan` is not read as emphasis.
const _tokenStart = '';
const _tokenEnd = '';
final _token = RegExp('$_tokenStart(\\d+)$_tokenEnd');

/// Tags that start a block. Line breaks next to them are layout, not text.
const _blockTags = {
  'p', 'div', 'blockquote', 'pre', 'ul', 'ol', 'li', 'table', 'thead', //
  'tbody', 'tr', 'th', 'td', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr',
  'details', 'summary', 'section', 'caption',
};

/// The `formatted_body` for [body], or null when plain text says it all.
///
/// [candidates] are the room's members: `@Name` for one of them becomes a
/// link to them, which every client draws as a pill.
String? markdownToMatrixHtml(
  String body, {
  List<MentionCandidate> candidates = const [],
}) {
  // Longest first: "Alice Smith" must win over "Alice".
  final named = [
    for (final c in [
      ...candidates,
    ]..sort((a, b) => b.displayName.length.compareTo(a.displayName.length)))
      if (c.displayName.isNotEmpty) c,
  ];
  var source = body;
  final used = <MentionCandidate>[];
  for (final candidate in named) {
    final plain = '@${candidate.displayName}';
    if (!source.contains(plain)) continue;
    source = source.replaceAll(plain, '$_tokenStart${used.length}$_tokenEnd');
    used.add(candidate);
  }

  final rendered = md.markdownToHtml(
    source,
    extensionSet: _extensions,
    inlineSyntaxes: [_SpoilerSyntax()],
  );

  final fragment = html_parser.parseFragment(rendered);
  _adapt(fragment, used, inCode: false);
  sanitizeMatrixHtml(fragment);
  _breakLines(fragment, inPre: false);
  _unwrapSingleParagraph(fragment);

  // Nothing but text, and the same text as typed: no reason to send HTML.
  final hasElements = fragment.nodes.any(
    (node) => node is dom.Element && node.localName != 'br',
  );
  if (!hasElements && fragment.text == body.replaceAll('\n', '')) {
    return null;
  }

  return serializeFragment(fragment).trim();
}

/// Rewrites the parts of the Markdown output Matrix has no HTML for.
void _adapt(
  dom.Node parent,
  List<MentionCandidate> used, {
  required bool inCode,
}) {
  for (final node in [...parent.nodes]) {
    if (node is dom.Text) {
      _restoreMentions(node, used, asText: inCode);
      continue;
    }
    if (node is! dom.Element) continue;

    final tag = node.localName;
    final cls = node.attributes['class'] ?? '';

    // Task lists: Matrix allows no form controls, so the box is a character.
    if (tag == 'input' && node.attributes['type'] == 'checkbox') {
      node.replaceWith(
        dom.Text(node.attributes.containsKey('checked') ? '☑ ' : '☐ '),
      );
      continue;
    }

    // GitHub's alerts (`> [!NOTE]`) become a quote with a bold title.
    if (tag == 'div' && cls.contains('markdown-alert')) {
      final quote = dom.Element.tag('blockquote');
      for (final child in [...node.nodes]) {
        if (child is dom.Element &&
            (child.attributes['class'] ?? '').contains(
              'markdown-alert-title',
            )) {
          final title = dom.Element.tag('strong')..text = child.text.trim();
          quote.append(dom.Element.tag('p')..append(title));
          continue;
        }
        quote.append(child);
      }
      node.replaceWith(quote);
      _adapt(quote, used, inCode: inCode);
      continue;
    }

    // Footnotes: the numbers are kept, the in-page jumps are not — a message
    // is not a page, and `#fn-1` would go nowhere.
    if (tag == 'a') {
      final href = node.attributes['href'] ?? '';
      if (cls.contains('footnote-backref')) {
        node.remove();
        continue;
      }
      if (href.startsWith('#')) {
        node.replaceWith(dom.Text(node.text));
        continue;
      }
    }
    if (tag == 'section' && cls.contains('footnotes')) {
      node.parentNode?.insertBefore(dom.Element.tag('hr'), node);
    }

    // An image in a message has to live on a homeserver (see matrix_html.dart),
    // so `![label](https://…)` is sent as a link to it instead.
    if (tag == 'img') {
      final src = node.attributes['src'] ?? '';
      if (!src.startsWith('mxc://')) {
        final link = dom.Element.tag('a')
          ..attributes['href'] = src
          ..text = node.attributes['alt']?.isNotEmpty == true
              ? node.attributes['alt']!
              : src;
        node.replaceWith(link);
        continue;
      }
    }

    _adapt(node, used, inCode: inCode || tag == 'code' || tag == 'pre');
  }
}

/// Turns mention tokens back into `@Name` — as a link, or as plain text
/// inside code, where a pill would change what the code says.
void _restoreMentions(
  dom.Text text,
  List<MentionCandidate> used, {
  required bool asText,
}) {
  final value = text.text;
  if (!value.contains(_tokenStart)) return;

  final parent = text.parentNode!;
  var last = 0;
  for (final match in _token.allMatches(value)) {
    final candidate = used[int.parse(match[1]!)];
    final label = '@${candidate.displayName}';
    parent.insertBefore(dom.Text(value.substring(last, match.start)), text);
    if (asText) {
      parent.insertBefore(dom.Text(label), text);
    } else {
      parent.insertBefore(
        dom.Element.tag('a')
          ..attributes['href'] =
              'https://matrix.to/#/${Uri.encodeComponent(candidate.userId)}'
          ..text = label,
        text,
      );
    }
    last = match.end;
  }
  parent.insertBefore(dom.Text(value.substring(last)), text);
  text.remove();
}

/// A single line break in chat means a line break, not the space Markdown
/// makes of it. Breaks next to a block are layout and are dropped; the rest
/// become `<br>`. Code blocks keep theirs.
void _breakLines(dom.Node parent, {required bool inPre}) {
  final nodes = [...parent.nodes];
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is dom.Element) {
      _breakLines(node, inPre: inPre || node.localName == 'pre');
      continue;
    }
    if (node is! dom.Text || inPre) continue;

    bool isBlock(dom.Node? n) =>
        n == null || (n is dom.Element && _blockTags.contains(n.localName));

    var value = node.text;
    if (isBlock(i == 0 ? null : nodes[i - 1])) {
      value = value.replaceFirst(RegExp(r'^\n+'), '');
    }
    if (isBlock(i == nodes.length - 1 ? null : nodes[i + 1])) {
      value = value.replaceFirst(RegExp(r'\n+$'), '');
    }
    if (value.isEmpty) {
      node.remove();
      continue;
    }
    if (!value.contains('\n')) {
      node.text = value;
      continue;
    }
    final lines = value.split('\n');
    for (var l = 0; l < lines.length; l++) {
      if (l > 0) parent.insertBefore(dom.Element.tag('br'), node);
      if (lines[l].isNotEmpty) parent.insertBefore(dom.Text(lines[l]), node);
    }
    node.remove();
  }
}

/// One paragraph and nothing else is sent without its `<p>`, the way every
/// other client sends a one-line message.
void _unwrapSingleParagraph(dom.DocumentFragment fragment) {
  final elements = fragment.nodes.whereType<dom.Element>().toList();
  final strayText = fragment.nodes.whereType<dom.Text>().any(
    (t) => t.text.trim().isNotEmpty,
  );
  if (elements.length != 1 || elements.single.localName != 'p' || strayText) {
    return;
  }
  final p = elements.single;
  fragment.nodes.removeWhere((n) => n is dom.Text);
  for (final child in [...p.nodes]) {
    fragment.insertBefore(child, p);
  }
  p.remove();
}
