// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import 'overlay_layout.dart';
import 'overlay_prefs_state.dart';

/// See the note on [OverlayPrefsState] for why this key is not per account.
const _prefsKey = 'overlay_prefs_v1';

/// Owns [OverlayPrefsState] and persists it.
///
/// Structurally a copy of `SecurityPrefsController`: read synchronously from
/// the preferences injected in `main()`, set state before the write so the
/// change is on screen immediately, and treat a failed write as a lost
/// preference rather than an error worth interrupting anybody over.
class OverlayPrefsController extends Notifier<OverlayPrefsState> {
  @override
  OverlayPrefsState build() {
    final raw = ref.read(prefsProvider).getString(_prefsKey);
    if (raw == null) return const OverlayPrefsState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const OverlayPrefsState();
      return OverlayPrefsState.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      // A blob we cannot read is a blob somebody else wrote, or one that got
      // truncated. Starting from defaults loses a layout; refusing to start
      // loses the overlay.
      return const OverlayPrefsState();
    }
  }

  void setEnabled(bool enabled) => _write(state.copyWith(enabled: enabled));

  void setMonitor(String monitorId) =>
      _write(state.copyWith(monitorId: monitorId));

  void setExcludeFromCapture(bool excluded) =>
      _write(state.copyWith(excludeFromCapture: excluded));

  void setToggleHotkey(OverlayHotkey hotkey) =>
      _write(state.copyWith(toggleHotkey: hotkey));

  void setEditHotkey(OverlayHotkey hotkey) =>
      _write(state.copyWith(editHotkey: hotkey));

  /// Replaces one layout, matched by id.
  ///
  /// [write] is false while a drag is in flight, for the reason the volume
  /// sliders take the same argument: a continuous gesture emits changes far
  /// faster than a write is worth, and the last one is the one that matters.
  void updateLayout(OverlayLayout layout, {bool write = true}) {
    final layouts = [
      for (final existing in state.layouts)
        existing.id == layout.id ? layout : existing,
    ];
    _write(state.copyWith(layouts: layouts), write: write);
  }

  /// Adds a layout and returns it, so the caller can select what it just made.
  OverlayLayout addLayout(String name, {OverlayLayout? copyOf}) {
    final id = _freshId();
    final layout = (copyOf ?? const OverlayLayout(id: '', name: '')).copyWith(
      name: name,
    );
    final created = OverlayLayout(
      id: id,
      name: layout.name,
      x: layout.x,
      y: layout.y,
      horizontal: layout.horizontal,
      avatarSize: layout.avatarSize,
      showNames: layout.showNames,
      idleOpacity: layout.idleOpacity,
    );
    _write(state.copyWith(layouts: [...state.layouts, created]));
    return created;
  }

  /// Removes a layout, and every assignment that pointed at it.
  ///
  /// Refuses to remove the last one: the overlay must always have somewhere to
  /// draw, and "you deleted your only layout" is not a state worth supporting.
  void removeLayout(String id) {
    if (state.layouts.length <= 1) return;

    final layouts = [
      for (final layout in state.layouts)
        if (layout.id != id) layout,
    ];
    final assignments = {
      for (final entry in state.assignments.entries)
        if (entry.value != id) entry.key: entry.value,
    };
    // Deleting what everything else falls back to has to leave a fallback.
    final defaultId = state.defaultLayoutId == id
        ? layouts.first.id
        : state.defaultLayoutId;

    _write(
      state.copyWith(
        layouts: layouts,
        assignments: assignments,
        defaultLayoutId: defaultId,
      ),
    );
  }

  void setDefaultLayout(String id) =>
      _write(state.copyWith(defaultLayoutId: id));

  /// Points [executable] at [layoutId].
  ///
  /// The other half of "several games, one HUD": this is what turns a layout
  /// somebody already likes into the one a newly-installed game gets, without
  /// copying anything. Editing that layout afterwards changes it everywhere,
  /// which is the point.
  void assign(String executable, String layoutId) {
    final exe = executable.toLowerCase();
    if (exe.isEmpty) return;
    _write(
      state.copyWith(
        assignments: {...state.assignments, exe: layoutId},
      ),
    );
  }

  void unassign(String executable) {
    final exe = executable.toLowerCase();
    if (!state.assignments.containsKey(exe)) return;
    final assignments = {...state.assignments}..remove(exe);
    _write(state.copyWith(assignments: assignments));
  }

  String _freshId() {
    // Monotonic and collision-free within an installation, which is all an id
    // has to be here: it never leaves this machine's preferences file.
    var candidate = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    while (state.layouts.any((layout) => layout.id == candidate)) {
      candidate = '$candidate.';
    }
    return candidate;
  }

  void _write(OverlayPrefsState next, {bool write = true}) {
    state = next;
    if (!write) return;
    ref.read(prefsProvider).setString(_prefsKey, jsonEncode(next.toJson()));
  }
}

final overlayPrefsProvider =
    NotifierProvider<OverlayPrefsController, OverlayPrefsState>(
      OverlayPrefsController.new,
    );
