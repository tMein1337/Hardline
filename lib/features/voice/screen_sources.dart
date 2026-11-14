// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// The two decisions the screen-share picker makes that are worth testing:
// which capture sources are worth offering, and what to call a share once
// several of them have the same name. Both are pure so they can be exercised
// without a capturer, a call, or a window manager.

/// Window titles that Windows reports as capturable and which are not.
///
/// Matched case-insensitively against the whole title, because these are shell
/// surfaces with fixed names rather than documents.
///
/// **Localised, which is the whole difficulty.** The taskbar overflow window —
/// the little panel of hidden tray icons — is reported as a shareable window on
/// every Windows install, in the display language of that install. Sharing it
/// produces a stream that is blank, or a few pixels tall, or simply fails; and
/// it sits in the list directly among real windows. Matching the English name
/// alone would leave the reporter's German machine exactly as it was.
///
/// This list is expected to grow. Add a name when one turns up rather than
/// trying to guess the set in advance: there is no API that says "this window
/// is a shell artefact", so the only honest approach is a denylist with the
/// heuristics below carrying everything it misses.
///
/// **Translations are not invented here.** A name added from a guess at what
/// another language calls the overflow window is a string that will never
/// match anything, and it would make the list look more complete than it is.
/// The entries below are either reported from a machine running that language
/// or — in the larger group — names Windows uses internally and does *not*
/// translate, which is why they carry no companions.
///
/// Note also what deliberately is not done: matching a *substring* like
/// "overflow" would catch every locale at once and is the obvious next idea.
/// It is wrong. A browser tab on Stack Overflow is titled "Stack Overflow —
/// Google Chrome", and dropping somebody's browser from the picker is a far
/// worse failure than leaving one dead entry in it.
const Set<String> kUnshareableWindowTitles = {
  // Taskbar overflow / hidden-icon flyout. Reported in the display language of
  // the install, so each of these came from a machine running it.
  'taskbar overflow window',
  'überlauffenster der taskleiste',
  'uberlauffenster der taskleiste',
  // The taskbar and shell surfaces themselves.
  'program manager',
  'programm-manager',
  'windows shell experience host',
  'windows-shell-oberflächenhost',
  '搜索',
  'start',
  'startmenü',
  'start menu',
  'search',
  'suchen',
  // Shell surfaces Windows names in English whatever the display language is,
  // so one entry each covers every install. All of them appear among the
  // capture sources and none of them can be shared usefully: the input host
  // and handwriting canvas are the on-screen keyboard and pen surfaces, and
  // the two switching overlays only exist while a key is held down.
  'windows input experience',
  'microsoft text input application',
  'shell handwriting canvas',
  'task switching',
  'snap assist',
  'desktop window manager',
  'windows default lock screen',
  'cortana',
  // Our own always-on-top HUD. It is also excluded from capture at the window
  // level, so this is belt and braces rather than the only guard.
  'hardline overlay',
};

/// Whether a capture source is worth putting in front of somebody.
///
/// Three rules, in order of how much they are trusted:
///
///  1. **A screen is always offered.** Monitors are few, named by index, and
///     never junk.
///  2. **A window with no title is dropped.** It cannot be identified in a
///     list, so choosing it would be guesswork, and in practice these are
///     invisible message-only windows.
///  3. **A window on [kUnshareableWindowTitles] is dropped**, and so is one
///     whose thumbnail is degenerate — zero or one pixel in either direction
///     means there is nothing on screen to capture.
///
/// [thumbnailWidth] and [thumbnailHeight] may be null when the capturer has not
/// produced a thumbnail yet; that is not evidence of anything, so it passes.
bool isShareableSource({
  required String name,
  required bool isWindow,
  int? thumbnailWidth,
  int? thumbnailHeight,
}) {
  if (!isWindow) return true;

  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;
  if (kUnshareableWindowTitles.contains(trimmed.toLowerCase())) return false;

  // Only judged once both dimensions are known. A capturer that has not got
  // round to the thumbnail yet reports nothing, and dropping a real window for
  // being slow would be worse than showing one dead one.
  if (thumbnailWidth != null && thumbnailHeight != null) {
    if (thumbnailWidth <= 1 || thumbnailHeight <= 1) return false;
  }

  return true;
}

/// Disambiguates shares that would otherwise read identically.
///
/// Two windows of the same program have the same title far more often than
/// not — two Explorer windows, two terminals, two documents — and a list of
/// three rows all saying "Untitled - Notepad" cannot be used to stop the right
/// one.
///
/// Names that are unique are left exactly as they are: numbering something
/// there is only one of would be noise. A name with duplicates gets ` 1`, ` 2`
/// and so on **in list order**, so the oldest share always holds the lowest
/// number. That is a property of the ordering, not of the numbering: the list
/// is append-ordered, so recomputing from scratch after a share is removed
/// renumbers the survivors and never leaves a hole.
List<String> numberedLabels(List<String> names) {
  final totals = <String, int>{};
  for (final name in names) {
    totals[name] = (totals[name] ?? 0) + 1;
  }

  final seen = <String, int>{};
  return [
    for (final name in names)
      if ((totals[name] ?? 0) < 2)
        name
      else
        '$name ${seen[name] = (seen[name] ?? 0) + 1}',
  ];
}
