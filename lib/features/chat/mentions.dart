// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// Turning `@name` in the composer into a mention on the wire, and back.
//
// Kept pure and away from widgets so both halves can be tested without a
// homeserver: the same file decides what to send and what a received message
// means, which is the only way the two stay in agreement.

/// One person offered by the composer's `@` completion.
class MentionCandidate {
  const MentionCandidate({
    required this.userId,
    required this.displayName,
    this.avatarMxc,
  });

  final String userId;
  final String displayName;
  final String? avatarMxc;
}

/// The `@…` being typed at [cursor], or null if the caret is not in one.
///
/// Returns the query without its `@`, plus where it starts, so the caller can
/// replace exactly that run.
///
/// The rules are deliberately tight, because a completion popup that opens
/// when it was not wanted is worse than one that occasionally does not:
///
///  * the `@` must start a word — at the beginning of the text or after
///    whitespace, so an email address does not trigger it;
///  * the query runs to the caret and may not contain whitespace, so the popup
///    closes as soon as somebody types past the name rather than staying open
///    over the rest of the sentence;
///  * an empty query is still a match, so the list appears the moment `@` is
///    typed rather than after a letter.
({String query, int start})? mentionQuery(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;

  final upToCursor = text.substring(0, cursor);
  final at = upToCursor.lastIndexOf('@');
  if (at < 0) return null;

  if (at > 0 && !_isBoundary(upToCursor.codeUnitAt(at - 1))) return null;

  final query = upToCursor.substring(at + 1);
  if (query.contains(RegExp(r'\s'))) return null;

  return (query: query, start: at);
}

bool _isBoundary(int codeUnit) {
  final char = String.fromCharCode(codeUnit);
  return char.trim().isEmpty;
}

/// [candidates] worth offering for [query], best first.
///
/// Matches on display name and on the id's localpart, because people reach for
/// both — and a prefix match ranks above a contained one, so typing `al` puts
/// Alice above Michal.
List<MentionCandidate> rankMentions(
  List<MentionCandidate> candidates,
  String query, {
  int limit = 8,
}) {
  final needle = query.toLowerCase();

  final prefix = <MentionCandidate>[];
  final contains = <MentionCandidate>[];

  for (final candidate in candidates) {
    final name = candidate.displayName.toLowerCase();
    final localpart = _localpart(candidate.userId).toLowerCase();

    if (needle.isEmpty || name.startsWith(needle) || localpart.startsWith(needle)) {
      prefix.add(candidate);
    } else if (name.contains(needle) || localpart.contains(needle)) {
      contains.add(candidate);
    }
  }

  int byName(MentionCandidate a, MentionCandidate b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  prefix.sort(byName);
  contains.sort(byName);

  return [...prefix, ...contains].take(limit).toList();
}

String _localpart(String userId) {
  final colon = userId.indexOf(':');
  final start = userId.startsWith('@') ? 1 : 0;
  return colon < 0 ? userId.substring(start) : userId.substring(start, colon);
}

/// The text after accepting [candidate] for the run starting at [start].
///
/// A trailing space is added because the next thing typed is always the rest
/// of the sentence, and because without one the completion would immediately
/// re-open on the name it had just inserted.
({String text, int cursor}) applyMention({
  required String text,
  required int start,
  required int cursor,
  required MentionCandidate candidate,
}) {
  // The `@` is kept. It is what the user typed, it is what makes the plain
  // body read correctly on a client that ignores the HTML, and — the part that
  // actually matters — it is what `mentionedUserIds` and `splitMentions` match
  // on. Dropping it here would mean the message looked right in the composer
  // and then went out with no mention in it at all.
  final inserted = '@${candidate.displayName} ';
  final next = text.replaceRange(start, cursor, inserted);
  return (text: next, cursor: start + inserted.length);
}

/// The `m.mentions` content for a message that names [userIds].
///
/// Empty when nobody is named — and the key is then omitted entirely rather
/// than sent as an empty list, which is what the spec asks for and what stops
/// every ordinary message carrying a mention block that means nothing.
Map<String, Object?> mentionsBlock(Set<String> userIds) =>
    userIds.isEmpty ? const {} : {'user_ids': userIds.toList()..sort()};

/// The people named in [body], as far as [candidates] can identify them.
///
/// Display names are matched longest-first: "Alice Smith" and "Alice" can both
/// be in a room, and matching the short one first would leave "Smith" dangling
/// outside the pill.
Set<String> mentionedUserIds(String body, List<MentionCandidate> candidates) {
  final sorted = [...candidates]
    ..sort((a, b) => b.displayName.length.compareTo(a.displayName.length));

  final found = <String>{};
  for (final candidate in sorted) {
    if (candidate.displayName.isEmpty) continue;
    if (body.contains('@${candidate.displayName}')) found.add(candidate.userId);
  }
  return found;
}

/// [body] with each mention rewritten as a `matrix.to` anchor.
///
/// The HTML half of the message. Element and every other client renders these
/// as a pill; a client that does not falls back to the plain body, which still
/// reads correctly because the anchor's label is the same text.
String formatMentions(String body, List<MentionCandidate> candidates) {
  final sorted = [...candidates]
    ..sort((a, b) => b.displayName.length.compareTo(a.displayName.length));

  var html = _escapeHtml(body);
  for (final candidate in sorted) {
    if (candidate.displayName.isEmpty) continue;
    final plain = '@${_escapeHtml(candidate.displayName)}';
    if (!html.contains(plain)) continue;
    // The `@` goes inside the anchor, so the pill Element draws covers the
    // whole thing — and so it matches the span `splitMentions` produces for
    // the same message locally. The two rendering paths must not disagree
    // about where a mention starts.
    final anchor =
        '<a href="https://matrix.to/#/${Uri.encodeComponent(candidate.userId)}">'
        '@${_escapeHtml(candidate.displayName)}</a>';
    html = html.replaceAll(plain, anchor);
  }
  return html;
}

String _escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
