// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// The HTML subset Matrix messages may carry, and the one sanitizer both
// directions go through: what this client sends and what it draws.
//
// The list is the spec's ("m.room.message msgtypes", `org.matrix.custom.html`)
// rather than anything wider. A tag outside it is unwrapped — its text kept,
// the tag dropped — except for the few whose content is not text at all
// (`script`, `style` and the like), which go entirely.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Tags kept as they are.
const _allowedTags = {
  'font', 'del', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'p', 'a', //
  'ul', 'ol', 'sup', 'sub', 'li', 'b', 'i', 'u', 'strong', 'em', 's', 'strike',
  'code', 'hr', 'br', 'div', 'table', 'thead', 'tbody', 'tr', 'th', 'td',
  'caption', 'pre', 'span', 'img', 'details', 'summary',
};

/// Tags dropped together with everything inside them.
const _droppedTags = {
  'script', 'style', 'head', 'title', 'iframe', 'object', 'embed', 'template',
  'noscript', 'svg', 'math', 'input', 'button', 'select', 'textarea',
  // The reply fallback: the quote is drawn from the replied-to event itself,
  // and the fallback is the sender's stale copy of it.
  'mx-reply',
};

/// Attributes kept, per tag. Anything else — `style`, `class` except a code
/// block's language, every `on…` handler — is removed.
const _allowedAttributes = <String, Set<String>>{
  'font': {'data-mx-bg-color', 'data-mx-color', 'color'},
  'span': {
    'data-mx-bg-color',
    'data-mx-color',
    'data-mx-spoiler',
    'data-mx-maths',
  },
  'div': {'data-mx-maths'},
  'a': {'href', 'name', 'target'},
  'img': {'width', 'height', 'alt', 'title', 'src', 'data-mx-emoticon'},
  'ol': {'start'},
  'code': {'class'},
};

/// Link schemes a message may point at.
const _allowedSchemes = {'http', 'https', 'ftp', 'mailto', 'magnet', 'matrix'};

/// How deep nesting may go before the rest is flattened to text. The spec
/// recommends a limit, and a renderer recursing per level needs one.
const maxHtmlDepth = 100;

/// Parses [html] and returns its sanitized fragment.
dom.DocumentFragment parseMatrixHtml(String html) {
  final fragment = html_parser.parseFragment(html);
  sanitizeMatrixHtml(fragment);
  return fragment;
}

/// Sanitizes [root] in place.
void sanitizeMatrixHtml(dom.Node root) => _sanitizeChildren(root, 0);

void _sanitizeChildren(dom.Node parent, int depth) {
  for (final node in [...parent.nodes]) {
    if (node is dom.Element) {
      _sanitizeElement(node, depth + 1);
    } else if (node is! dom.Text) {
      // Comments, processing instructions.
      node.remove();
    }
  }
}

void _sanitizeElement(dom.Element element, int depth) {
  final tag = element.localName ?? '';

  if (_droppedTags.contains(tag)) {
    element.remove();
    return;
  }

  if (depth > maxHtmlDepth) {
    element.replaceWith(dom.Text(element.text));
    return;
  }

  if (!_allowedTags.contains(tag)) {
    // Unwrap: keep what is inside, lose the tag.
    _sanitizeChildren(element, depth);
    final parent = element.parentNode;
    if (parent == null) return;
    for (final child in [...element.nodes]) {
      parent.insertBefore(child, element);
    }
    element.remove();
    return;
  }

  final allowed = _allowedAttributes[tag] ?? const <String>{};
  element.attributes.removeWhere(
    (name, _) => !allowed.contains(name.toString()),
  );

  switch (tag) {
    case 'a':
      final href = element.attributes['href'];
      if (href != null && !_isAllowedLink(href)) {
        element.attributes.remove('href');
      }
    case 'img':
      // Only media on a homeserver. An http image would load from wherever
      // the sender pointed it, telling that server who read the message.
      final src = element.attributes['src'];
      if (src == null || !src.startsWith('mxc://')) {
        final label = element.attributes['alt'] ?? element.attributes['title'];
        element.replaceWith(dom.Text(label ?? ''));
        return;
      }
    case 'code':
      final cls = element.attributes['class'];
      if (cls != null && !RegExp(r'^language-[\w+#.-]+$').hasMatch(cls)) {
        element.attributes.remove('class');
      }
  }

  _sanitizeChildren(element, depth);
}

bool _isAllowedLink(String href) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null || !uri.hasScheme) return false;
  return _allowedSchemes.contains(uri.scheme.toLowerCase());
}

/// The HTML of a fragment's children, serialized.
String serializeFragment(dom.Node root) => root.nodes.map(_serialize).join();

String _serialize(dom.Node node) =>
    node is dom.Element ? node.outerHtml : (node as dom.Text).text.htmlEscaped;

extension on String {
  String get htmlEscaped =>
      replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
