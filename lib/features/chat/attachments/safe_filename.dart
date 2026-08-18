// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Turns a filename that came off the network into one that is safe to hand to
/// a save dialog.
///
/// The name on an `m.file` event is written by whoever sent it. It reaches us
/// as an arbitrary string and goes straight into `getSaveLocation`, which is
/// the last point at which it is still ours to correct.
///
/// The concrete things being defended against, all of which are ordinary
/// content in a Matrix event:
///
///   * **Directory components.** `..\..\Windows\System32\evil.dll` as a
///     suggested name pre-navigates the dialog somewhere the user did not
///     choose. Only the final segment is ever wanted.
///   * **Bidirectional overrides.** A right-to-left override (U+202E) placed
///     inside a name reverses how the rest of it is drawn, so the extension a
///     user reads is not the extension they get. It is the most effective
///     filename trick there is and it costs one invisible character. (Named
///     rather than shown: a literal one in this file would play the same trick
///     on whoever reads the source.)
///   * **Windows device names.** `CON`, `NUL`, `COM1` and friends are not
///     filenames; opening one talks to a device.
///   * **Trailing dots and spaces**, which Windows silently strips, so
///     `evil.exe.` and `evil.exe` are the same file while looking different.
///   * **Characters Windows refuses** (`<>:"/\|?*`), control characters, and
///     names long enough to hit `MAX_PATH`.
///
/// Deliberately conservative: it is better to hand the dialog a slightly
/// mangled name that the user can edit than a well-formed name that is not what
/// it appears to be. The user still confirms the final path in the dialog —
/// this only ensures they are confirming what they think they are.
library;

/// The longest name this will produce, extension included.
///
/// Well under `MAX_PATH` (260) so that a long directory still leaves room, and
/// far past anything a person types on purpose.
const kMaxFilenameLength = 120;

/// Used when nothing usable survives sanitisation.
const kFallbackFilename = 'attachment';

/// Characters Windows rejects in a filename, plus both separators.
final _illegal = RegExp(r'[<>:"/\\|?*]');

/// Control characters, zero-width characters and the Unicode bidi controls
/// that make an extension lie.
///
/// Assembled from code points rather than written as literals or escapes. A
/// literal override character here would reorder this file for anyone reading
/// it — exactly the attack being filtered — and an escape sequence is one
/// careless copy-paste away from becoming a literal.
final _invisible = RegExp(
  '['
  '${_range(0x0000, 0x001F)}' // C0 controls, including NUL
  '${_range(0x007F, 0x009F)}' // DEL and the C1 controls
  '${_range(0x200B, 0x200F)}' // zero-width spaces, LRM, RLM
  '${_range(0x202A, 0x202E)}' // LRE, RLE, PDF, LRO, RLO
  '${_range(0x2066, 0x2069)}' // LRI, RLI, FSI, PDI
  '${_char(0xFEFF)}' // zero-width no-break space / BOM
  ']',
);

String _char(int code) => String.fromCharCode(code);

String _range(int from, int to) => '${_char(from)}-${_char(to)}';

/// Names that address a device rather than a file, with or without extension.
const _reservedStems = {
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// [raw] reduced to something safe to suggest in a save dialog.
///
/// Always returns a non-empty name with no directory component.
String safeFilename(String raw) {
  // Last path segment only. Both separators, because the string did not
  // necessarily come from this platform.
  var name = raw.split(RegExp(r'[/\\]')).last;

  name = name.replaceAll(_invisible, '');
  name = name.replaceAll(_illegal, '_');

  // `.` and `..` survive the steps above and are not names.
  if (name == '.' || name == '..') name = '';

  // Windows strips these silently, so strip them visibly instead.
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  name = name.trim();

  if (name.isEmpty) return kFallbackFilename;

  name = _defuseReservedName(name);
  name = _clampLength(name);

  // The length clamp can strip a name back to nothing if it was all extension.
  return name.isEmpty ? kFallbackFilename : name;
}

/// Prefixes a reserved device name so it becomes an ordinary file.
///
/// The check is on the stem, because `CON.txt` is still `CON` to Windows.
String _defuseReservedName(String name) {
  final dot = name.indexOf('.');
  final stem = dot == -1 ? name : name.substring(0, dot);
  if (!_reservedStems.contains(stem.toLowerCase())) return name;
  return '_$name';
}

/// Shortens the stem rather than the extension.
///
/// Truncating the other way would turn `report.pdf` into `report.p`, which
/// changes what the file *is* — the thing this module exists to preserve.
String _clampLength(String name) {
  if (name.length <= kMaxFilenameLength) return name;

  final dot = name.lastIndexOf('.');
  // An "extension" longer than this is not one; treat the whole as a stem.
  if (dot <= 0 || name.length - dot > 12) {
    return name.substring(0, kMaxFilenameLength);
  }

  final extension = name.substring(dot);
  final keep = kMaxFilenameLength - extension.length;
  if (keep <= 0) return name.substring(0, kMaxFilenameLength);
  return name.substring(0, keep) + extension;
}
