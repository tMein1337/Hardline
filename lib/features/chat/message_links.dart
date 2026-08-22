// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// One run of a message body: plain text, or a link and where it points.
///
/// Concatenating every [text] in order reproduces the body character for
/// character. Nothing is rewritten, hidden or inserted, which is what makes a
/// detected link safe to show without an "are you sure" step: the label *is*
/// the target, so there is nothing to disguise. That property depends on the
/// body being plain text — see `message_body.dart`.
@immutable
class BodySpan {
  const BodySpan.text(this.text) : target = null;
  const BodySpan.link(this.text, Uri this.target);

  final String text;

  /// Null on a plain run.
  final Uri? target;

  bool get isLink => target != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodySpan && text == other.text && target == other.target;

  @override
  int get hashCode => Object.hash(text, target);

  @override
  String toString() =>
      isLink ? 'BodySpan.link($text -> $target)' : 'BodySpan.text($text)';
}

/// `http` and `https` only, and only where they are written out.
///
/// Deliberately not a bare `www.`, and not `mailto:` or `matrix:`: any of those
/// would need a scheme invented for them, and the moment the target stops being
/// exactly the text on screen, a link stops being self-evident. They are rare
/// enough in a plain-text body that leaving them as text costs less than
/// guessing wrong.
///
/// The word boundary keeps `xhttps://…` — or the tail of some longer token —
/// from being read as a link.
final _url = RegExp(r'\bhttps?://\S+', caseSensitive: false);

/// Punctuation that ends a sentence far more often than it ends a URL.
const _trailingPunctuation = '.,;:!?\'"';

/// Closing brackets, and what opens them. A Wikipedia article with a
/// disambiguation suffix really does end in `)`, so these can only be dropped
/// when the match has more closers than openers — which is what happens when
/// somebody writes (see https://example.org) or <https://example.org>.
const _brackets = <String, String>{')': '(', ']': '[', '}': '{', '>': '<'};

/// Splits [body] into plain runs and link runs.
///
/// Anything trimmed off the end of a link stays in the text run that follows,
/// so the body is never altered — only divided.
List<BodySpan> splitBodyLinks(String body) {
  if (body.isEmpty) return const <BodySpan>[];

  final spans = <BodySpan>[];
  var cursor = 0;

  for (final match in _url.allMatches(body)) {
    // A match inside an already-consumed run cannot happen with \S+, but the
    // cursor is what guarantees the output reassembles, so it is checked.
    if (match.start < cursor) continue;

    final candidate = _trimTrailing(match[0]!);
    final target = _parseTarget(candidate);
    if (target == null) continue;

    if (match.start > cursor) {
      spans.add(BodySpan.text(body.substring(cursor, match.start)));
    }
    spans.add(BodySpan.link(candidate, target));
    cursor = match.start + candidate.length;
  }

  if (cursor < body.length) spans.add(BodySpan.text(body.substring(cursor)));
  return spans;
}

String _trimTrailing(String candidate) {
  var end = candidate.length;

  while (end > 0) {
    final last = candidate[end - 1];
    if (_trailingPunctuation.contains(last)) {
      end--;
      continue;
    }

    final opener = _brackets[last];
    if (opener != null &&
        _countBefore(candidate, last, end) >
            _countBefore(candidate, opener, end)) {
      end--;
      continue;
    }

    break;
  }

  return candidate.substring(0, end);
}

int _countBefore(String text, String character, int end) {
  var count = 0;
  for (var i = 0; i < end; i++) {
    if (text[i] == character) count++;
  }
  return count;
}

/// Rejects anything that survived trimming but is not addressable — `https://`
/// on its own, most obviously.
Uri? _parseTarget(String candidate) {
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) return null;
  return uri;
}

/// What a `matrix.to` link names, when it names something Matrix rather than
/// something on the web.
@immutable
class MatrixToTarget {
  const MatrixToTarget({required this.identifier, this.eventId});

  /// A room id (`!x:server`), a published alias (`#x:server`) or a user
  /// (`@x:server`). matrix.to does not label which; the sigil is the label.
  final String identifier;

  /// Set when the link points at one message rather than at the room.
  final String? eventId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatrixToTarget &&
          identifier == other.identifier &&
          eventId == other.eventId;

  @override
  int get hashCode => Object.hash(identifier, eventId);

  @override
  String toString() => 'MatrixToTarget($identifier, event: $eventId)';
}

/// Reads a `matrix.to` permalink, or null if [url] is an ordinary web address.
///
/// The whole payload lives in the *fragment* — `#/%21room%3Aserver/%24event` —
/// which is why matrix.to works as a static page, and why the `?via=` hint
/// hangs off the fragment rather than being the URL's own query. Dart hands
/// back the fragment undecoded, so every part is decoded here.
MatrixToTarget? parseMatrixTo(Uri url) {
  if (url.host.toLowerCase() != 'matrix.to') return null;

  var fragment = url.fragment;
  if (!fragment.startsWith('/')) return null;

  final via = fragment.indexOf('?');
  if (via != -1) fragment = fragment.substring(0, via);

  final parts = fragment
      .substring(1)
      .split('/')
      .map(_decodePart)
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;

  final identifier = parts.first;
  if (!identifier.startsWith('!') &&
      !identifier.startsWith('#') &&
      !identifier.startsWith('@')) {
    return null;
  }

  final event = parts.length > 1 ? parts[1] : null;
  return MatrixToTarget(
    identifier: identifier,
    eventId: event != null && event.startsWith(r'$') ? event : null,
  );
}

String _decodePart(String part) {
  try {
    return Uri.decodeComponent(part);
  } catch (_) {
    // A hand-typed link with a stray % is not worth failing over; the raw text
    // simply will not match a room, and the browser gets it instead.
    return part;
  }
}
