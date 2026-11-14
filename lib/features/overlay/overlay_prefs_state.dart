// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import '../hotkeys/hotkey.dart';
import 'overlay_layout.dart';

/// The id every installation starts with, and the one assignments fall back to.
const kDefaultOverlayLayoutId = 'default';

/// How long the HUD stays up after the last person stops talking.
///
/// The overlay fades as a whole rather than per person — a layered window has
/// no per-pixel alpha to give the widgets, see `kChromaKey`. On its own that
/// would mean the roster snapping to its idle opacity the instant a sentence
/// ended, which reads as flicker in an ordinary back-and-forth conversation.
/// Holding it up for a moment afterwards is what makes a window-wide fade feel
/// like the per-person one it replaced.
///
/// The range is deliberately enormous, because the two ends are both real
/// answers rather than a default and some slack around it: a tenth of a second
/// is "show me only who is talking, right now", and an hour is "once the call
/// gets going, leave it up". Neither is wrong.
const kDefaultOverlayLinger = Duration(seconds: 2);
const kMinOverlayLinger = Duration(milliseconds: 100);
const kMaxOverlayLinger = Duration(hours: 1);

/// The overlay's settings, layouts and per-application assignments.
///
/// **Flat, not namespaced by user id**, following `security_prefs.dart` and the
/// theme rather than the voice and activity preferences. The rule the codebase
/// applies: a key that holds opinions about *other people* — volumes, mutes,
/// who is followed — is per account, because a shared computer must not leak
/// those between logins. A screen layout is not that. It answers "where on this
/// monitor do I want things", which does not change when a different account
/// signs in.
@immutable
class OverlayPrefsState {
  const OverlayPrefsState({
    this.enabled = false,
    this.monitorId = '',
    this.excludeFromCapture = true,
    this.layouts = const [
      OverlayLayout(id: kDefaultOverlayLayoutId, name: 'Default'),
    ],
    this.assignments = const {},
    this.defaultLayoutId = kDefaultOverlayLayoutId,
    this.toggleHotkey = const Hotkey(
      modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
      key: 0x4F, // O
    ),
    this.editHotkey = const Hotkey(
      modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
      key: 0x50, // P
    ),
    this.linger = kDefaultOverlayLinger,
  });

  factory OverlayPrefsState.fromJson(Map<String, Object?> json) {
    final rawLayouts = json['layouts'];
    var layouts = <OverlayLayout>[];
    if (rawLayouts is List) {
      for (final entry in rawLayouts) {
        if (entry is Map) {
          layouts.add(OverlayLayout.fromJson(entry.cast<String, Object?>()));
        }
      }
    }
    // Never empty. A file that lost its layouts must come back with somewhere
    // to draw, not with an overlay that silently refuses to appear.
    if (layouts.isEmpty) {
      layouts = const [
        OverlayLayout(id: kDefaultOverlayLayoutId, name: 'Default'),
      ];
    }

    final assignments = <String, String>{};
    final rawAssignments = json['assignments'];
    if (rawAssignments is Map) {
      for (final entry in rawAssignments.entries) {
        final exe = entry.key;
        final layoutId = entry.value;
        if (exe is! String || layoutId is! String) continue;
        // An assignment to a layout that has since been deleted is dropped
        // rather than kept as a dangling id. Resolution falls back anyway, but
        // a rule that never writes a broken reference is easier to trust than
        // one that tolerates them.
        if (!layouts.any((layout) => layout.id == layoutId)) continue;
        assignments[exe.toLowerCase()] = layoutId;
      }
    }

    final rawDefault = json['defaultLayoutId'];
    final defaultId =
        rawDefault is String && layouts.any((layout) => layout.id == rawDefault)
        ? rawDefault
        : layouts.first.id;

    final toggle = json['toggleHotkey'];
    final edit = json['editHotkey'];

    return OverlayPrefsState(
      enabled: json['enabled'] is bool ? json['enabled']! as bool : false,
      monitorId: json['monitorId'] is String
          ? json['monitorId']! as String
          : '',
      excludeFromCapture: json['excludeFromCapture'] is bool
          ? json['excludeFromCapture']! as bool
          : true,
      layouts: layouts,
      assignments: assignments,
      defaultLayoutId: defaultId,
      toggleHotkey: toggle is Map
          ? Hotkey.fromJson(toggle.cast<String, Object?>())
          : const OverlayPrefsState().toggleHotkey,
      editHotkey: edit is Map
          ? Hotkey.fromJson(edit.cast<String, Object?>())
          : const OverlayPrefsState().editHotkey,
      // Clamped at parse rather than at use, like the tooltip delay: a
      // hand-edited value outside the range would otherwise be a HUD that
      // never comes back with nothing on screen to explain it.
      linger: json['lingerMs'] is int
          ? Duration(
              milliseconds: (json['lingerMs']! as int).clamp(
                kMinOverlayLinger.inMilliseconds,
                kMaxOverlayLinger.inMilliseconds,
              ),
            )
          : kDefaultOverlayLinger,
    );
  }

  final bool enabled;

  /// The monitor device name to cover. Empty means the primary one, which is
  /// also where an unplugged monitor's layout ends up.
  final String monitorId;

  /// Keep the overlay out of screen captures.
  ///
  /// On by default: the HUD exists so *you* can see who is talking, and a
  /// screen share carrying your own overlay shows everyone else a copy of
  /// themselves.
  final bool excludeFromCapture;

  final List<OverlayLayout> layouts;

  /// Executable basename, lowercased, to layout id.
  ///
  /// Many-to-one on purpose. Assigning a second game to a layout you already
  /// like is the difference between adopting a HUD and rebuilding it.
  final Map<String, String> assignments;

  /// What anything unassigned gets.
  final String defaultLayoutId;

  /// Where the overlay's chords used to be bound. **Read for migration only.**
  ///
  /// `HotkeysController` owns every global chord now, including these two, and
  /// reads them out of this blob once to carry them over — see
  /// `_adoptOverlayChords`. Nothing here registers or dispatches them, and
  /// there is no setter: editing these would change a value nothing reads.
  ///
  /// They are still parsed and still written back, deliberately. The adoption
  /// happens the first time the hotkey store is built, and the overlay's own
  /// preferences may well be written before that — so dropping the keys on
  /// write would race the migration and lose a customised chord.
  final Hotkey toggleHotkey;
  final Hotkey editHotkey;

  /// See [kDefaultOverlayLinger].
  final Duration linger;

  /// The layout for [executable], falling back to the default.
  ///
  /// Total by construction: [layouts] is never empty and the default id is
  /// validated at parse time, so this never has to answer "nothing".
  OverlayLayout layoutFor(String executable) {
    final assigned = assignments[executable.toLowerCase()];
    return layoutById(assigned ?? defaultLayoutId);
  }

  OverlayLayout layoutById(String id) => layouts.firstWhere(
    (layout) => layout.id == id,
    orElse: () => layouts.firstWhere(
      (layout) => layout.id == defaultLayoutId,
      orElse: () => layouts.first,
    ),
  );

  /// Every executable pointing at [layoutId], sorted for a stable list.
  List<String> executablesFor(String layoutId) =>
      (assignments.entries
            .where((entry) => entry.value == layoutId)
            .map((entry) => entry.key)
            .toList())
        ..sort();

  OverlayPrefsState copyWith({
    bool? enabled,
    String? monitorId,
    bool? excludeFromCapture,
    List<OverlayLayout>? layouts,
    Map<String, String>? assignments,
    String? defaultLayoutId,
    Duration? linger,
  }) => OverlayPrefsState(
    enabled: enabled ?? this.enabled,
    monitorId: monitorId ?? this.monitorId,
    excludeFromCapture: excludeFromCapture ?? this.excludeFromCapture,
    layouts: layouts ?? this.layouts,
    assignments: assignments ?? this.assignments,
    defaultLayoutId: defaultLayoutId ?? this.defaultLayoutId,
    toggleHotkey: toggleHotkey,
    editHotkey: editHotkey,
    linger: linger ?? this.linger,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'enabled': enabled,
    'monitorId': monitorId,
    'excludeFromCapture': excludeFromCapture,
    'layouts': [for (final layout in layouts) layout.toJson()],
    'assignments': assignments,
    'defaultLayoutId': defaultLayoutId,
    'toggleHotkey': toggleHotkey.toJson(),
    'editHotkey': editHotkey.toJson(),
    'lingerMs': linger.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlayPrefsState &&
          enabled == other.enabled &&
          monitorId == other.monitorId &&
          excludeFromCapture == other.excludeFromCapture &&
          listEquals(layouts, other.layouts) &&
          mapEquals(assignments, other.assignments) &&
          defaultLayoutId == other.defaultLayoutId &&
          toggleHotkey == other.toggleHotkey &&
          editHotkey == other.editHotkey &&
          linger == other.linger;

  @override
  int get hashCode => Object.hash(
    enabled,
    monitorId,
    excludeFromCapture,
    Object.hashAll(layouts),
    Object.hashAllUnordered(
      assignments.entries.map((e) => '${e.key}=${e.value}'),
    ),
    defaultLayoutId,
    toggleHotkey,
    editHotkey,
    linger,
  );
}
