// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// One or two letters standing in for a missing avatar.
///
/// Rune-based so emoji and non-Latin names are not split mid-character, which
/// `substring` would happily do.
String initialsOf(String name) {
  final words = name
      .split(RegExp(r'[\s_\-.]+'))
      .where((word) => word.isNotEmpty)
      .toList();

  if (words.isEmpty) return '?';
  if (words.length == 1) return _firstRunes(words.first, 2);
  return '${_firstRunes(words[0], 1)}${_firstRunes(words[1], 1)}';
}

String _firstRunes(String value, int count) {
  // Matrix ids and aliases start with a sigil that carries no meaning here.
  final trimmed = value.replaceFirst(RegExp(r'^[@#!+]'), '');
  if (trimmed.isEmpty) return '?';

  final runes = trimmed.runes.toList();
  final take = runes.length < count ? runes.length : count;
  return String.fromCharCodes(runes.take(take)).toUpperCase();
}
