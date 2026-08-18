// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Makes a name chosen by somebody else safe to draw in a row.
///
/// Display names and room names are free text set by whoever owns them. They
/// arrive from the homeserver and go straight into a `Text` widget, which is
/// where three ordinary things become problems:
///
///   * **Bidi overrides.** A name can carry U+202E and reorder everything
///     drawn after it, including the text of the *next* widget in some
///     layouts. In a member list this is how one person's name is made to read
///     as another's — the strongest impersonation trick available to someone
///     who cannot change their user id.
///   * **Newlines and control characters.** A name containing `\n` turns a
///     one-line row into a multi-line one, pushing the rest of the list around;
///     a long run of them pushes it off screen.
///   * **Length.** Nothing on the protocol side caps a display name, and a row
///     is not the place to discover that.
///
/// Applied at the *ingestion* points — where a name is read out of the SDK —
/// rather than at each `Text`. There are fifteen of the former and well over a
/// hundred of the latter, and a rule enforced in fifteen places is one that
/// stays enforced.
///
/// Deliberately gentle about scripts. Right-to-left text is not the problem and
/// must keep rendering correctly, so the directional *marks* (U+200E, U+200F)
/// are left alone; only the explicit override, embedding and isolate controls
/// are removed. A Hebrew or Arabic name comes through unchanged.
library;

/// The longest name that will be returned.
///
/// Long enough for any real name including a long room title, short enough that
/// a row cannot be used as a battering ram.
const kMaxDisplayNameLength = 100;

/// Characters that reorder or hide text, assembled from code points.
///
/// Written this way rather than as literals or escapes for the same reason as
/// in `safe_filename.dart`: a literal override in this file would reorder the
/// source for whoever reads it.
final _dangerous = RegExp(
  '['
  '${_range(0x0000, 0x0008)}' // C0 controls, keeping tab/newline for the
  '${_range(0x000B, 0x001F)}' // whitespace pass below to collapse
  '${_range(0x007F, 0x009F)}' // DEL and C1 controls
  '${_range(0x200B, 0x200D)}' // zero-width space / non-joiner / joiner
  '${_range(0x202A, 0x202E)}' // LRE, RLE, PDF, LRO, RLO
  '${_range(0x2066, 0x2069)}' // LRI, RLI, FSI, PDI
  '${_char(0xFEFF)}' // zero-width no-break space
  ']',
);

String _char(int code) => String.fromCharCode(code);

String _range(int from, int to) => '${_char(from)}-${_char(to)}';

/// [raw] reduced to a single line that is safe to draw.
///
/// Returns [fallback] when nothing legible survives, so a caller never has to
/// render an empty row.
String displaySafeName(String? raw, {String fallback = 'Unknown'}) {
  if (raw == null) return fallback;

  var name = raw.replaceAll(_dangerous, '');
  // Any remaining whitespace — including the tab and newline deliberately left
  // above — becomes a single space, so a name is always one line.
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (name.isEmpty) return fallback;

  if (name.length > kMaxDisplayNameLength) {
    // A trailing ellipsis rather than a hard cut, so a truncated name is
    // visibly truncated instead of looking like somebody's actual name.
    name = '${name.substring(0, kMaxDisplayNameLength - 1).trimRight()}…';
  }
  return name;
}
