/// Hex colour text, shared by the slot editor and the theme file format.
///
/// It lives in `theme/` rather than beside the editor that first needed it
/// because the file codec needs the same parser, and `theme/` importing a
/// settings widget would point the dependency backwards.
library;

import 'package:flutter/material.dart';

/// `#AARRGGBB`, the lossless form. What an exported theme file contains.
///
/// Alpha is always written, even when opaque: a few slots (`scrim`,
/// `dropOverlay`, `voiceParticipantRow`) are deliberately translucent, and a
/// format that sometimes omits alpha would turn one of those washes into a
/// solid block on the round trip.
String hexOf(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// `#RRGGBB`, as a design tool would write it. What the editor's field shows.
String hexRgbOf(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses hex in the two shapes people actually paste.
///
/// Null for anything unparseable, so a half-typed value leaves the editor's
/// preview alone instead of flashing black on every keystroke, and a bad line
/// in a theme file falls back to the palette instead of to transparent.
Color? parseHexColor(String raw) {
  final text = raw.trim().replaceFirst('#', '');
  if (text.length != 6 && text.length != 8) return null;
  final value = int.tryParse(text, radix: 16);
  if (value == null) return null;
  // Six digits mean the user gave no alpha, and a theme slot is opaque unless
  // it says otherwise — defaulting to transparent would blank a whole surface.
  return Color(text.length == 6 ? 0xFF000000 | value : value);
}
