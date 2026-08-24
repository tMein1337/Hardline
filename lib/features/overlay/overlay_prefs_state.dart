// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'overlay_layout.dart';

/// The id every installation starts with, and the one assignments fall back to.
const kDefaultOverlayLayoutId = 'default';

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
    this.layouts = const [OverlayLayout(id: kDefaultOverlayLayoutId, name: 'Default')],
    this.assignments = const {},
    this.defaultLayoutId = kDefaultOverlayLayoutId,
    this.toggleHotkey = const OverlayHotkey(
      modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
      key: 0x4F, // O
    ),
    this.editHotkey = const OverlayHotkey(
      modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
      key: 0x50, // P
    ),
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
        rawDefault is String &&
            layouts.any((layout) => layout.id == rawDefault)
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
          ? OverlayHotkey.fromJson(toggle.cast<String, Object?>())
          : const OverlayPrefsState().toggleHotkey,
      editHotkey: edit is Map
          ? OverlayHotkey.fromJson(edit.cast<String, Object?>())
          : const OverlayPrefsState().editHotkey,
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

  final OverlayHotkey toggleHotkey;
  final OverlayHotkey editHotkey;

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
    OverlayHotkey? toggleHotkey,
    OverlayHotkey? editHotkey,
  }) => OverlayPrefsState(
    enabled: enabled ?? this.enabled,
    monitorId: monitorId ?? this.monitorId,
    excludeFromCapture: excludeFromCapture ?? this.excludeFromCapture,
    layouts: layouts ?? this.layouts,
    assignments: assignments ?? this.assignments,
    defaultLayoutId: defaultLayoutId ?? this.defaultLayoutId,
    toggleHotkey: toggleHotkey ?? this.toggleHotkey,
    editHotkey: editHotkey ?? this.editHotkey,
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
          editHotkey == other.editHotkey;

  @override
  int get hashCode => Object.hash(
    enabled,
    monitorId,
    excludeFromCapture,
    Object.hashAll(layouts),
    Object.hashAllUnordered(assignments.entries.map((e) => '${e.key}=${e.value}')),
    defaultLayoutId,
    toggleHotkey,
    editHotkey,
  );
}
