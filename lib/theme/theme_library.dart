// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/injected_providers.dart';
import 'palettes.dart';
import 'theme_entry.dart';

const _prefsKey = 'theme_library_v1';

/// Every theme the user has, and the only thing allowed to change one.
///
/// Follows `AccountRegistry` exactly: a synchronous read from the preferences
/// injected in `main()`, so the first frame is already correctly themed, and a
/// `_persist` that sets state before writing so a repaint never waits on disk.
///
/// Which theme is *active* is not here — `AppThemeState.presetId` already held
/// that and still does, so there is one answer to that question rather than two
/// that can disagree.
class ThemeLibrary extends Notifier<ThemeLibraryState> {
  @override
  ThemeLibraryState build() {
    final raw = ref.watch(prefsProvider).getString(_prefsKey);
    if (raw == null) return ThemeLibraryState.seeded();

    try {
      final stored = ThemeLibraryState.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
      // An empty list is as unusable as a corrupt one: with no themes there is
      // nothing to select, nothing to edit, and nothing to duplicate from.
      return stored.isEmpty ? ThemeLibraryState.seeded() : stored;
    } catch (error, stack) {
      // A corrupt or hand-edited library must never prevent startup, and
      // re-seeding at least leaves the app usable and recognisable.
      debugPrint('Ignoring unreadable theme library: $error\n$stack');
      return ThemeLibraryState.seeded();
    }
  }

  /// Adds [entry] at the end, renaming it if the name is taken.
  /// Returns the id it was stored under.
  /// The id is returned rather than awaited because every caller's next act is
  /// to select the new theme, which cannot wait for a disk write.
  String add(ThemeEntry entry) {
    final named = entry.copyWith(name: state.uniqueName(entry.name));
    unawaited(_persist(state.copyWith(entries: [...state.entries, named])));
    return named.id;
  }

  /// An independent copy of [id], inserted directly below it.
  ///
  /// Copies every slot and the avatar ramp verbatim — see [ThemeEntry.copyAs],
  /// which rebuilds both rather than sharing them. Applying the copy is
  /// pixel-identical to applying the original, which is what makes duplicating
  /// the safe way to experiment on a theme instead of editing it.
  ///
  /// The copy is never seeded: it gets a generated id, so the original stays
  /// revertible and restorable while the copy is freely editable.
  ///
  /// Returns the new id so the caller can switch to it. Editing the original by
  /// mistake, having meant to edit the copy, is the obvious trap here.
  String duplicate(String id) {
    final source = state.byId(id);
    if (source == null) return id;

    final copy = source.copyAs(
      id: generateThemeId(),
      name: state.uniqueName('${source.name} (copy)'),
    );

    final entries = [...state.entries];
    entries.insert(state.indexOf(id) + 1, copy);
    unawaited(_persist(state.copyWith(entries: entries)));
    return copy.id;
  }

  Future<void> rename(String id, String name) => _update(
    id,
    (entry) =>
        entry.copyWith(name: state.uniqueName(name, exceptId: id)),
  );

  /// Sets one slot of one theme.
  ///
  /// [commit] false while a colour slider is being dragged: state updates so
  /// the app recolors under the pointer, but the write waits for the release.
  /// The same deliberate exception `ThemeController.setTooltipDelay` and
  /// `VoicePrefsController` make, and for the same reason — every frame would
  /// otherwise be a separate write of a value nobody has settled on.
  Future<void> setSlot(
    String id,
    String slot,
    Color color, {
    bool commit = true,
  }) => _update(
    id,
    (entry) => entry.copyWith(colors: {slot: color.toARGB32()}),
    write: commit,
  );

  /// Puts one slot back to what the built-in palette of the same id says.
  ///
  /// A no-op for a theme the user made or imported: it was never a copy of a
  /// built-in, so there is nothing to go back to.
  Future<void> revertSlot(String id, String slot) {
    final builtIn = AppPalettes.byIdMap[id];
    if (builtIn == null) return Future.value();
    return setSlot(id, slot, builtIn.slot(slot));
  }

  /// Removes a theme. A no-op for the last one.
  ///
  /// The library is never allowed to empty: `presetId` would then name nothing,
  /// and while `AppPalettes.byId` falls back to dark rather than crashing,
  /// the appearance pane would offer an empty list and no way out of it. The
  /// pane disables the action too — this is the backstop, not the message.
  Future<void> remove(String id) {
    if (state.entries.length <= 1) return Future.value();
    return _persist(
      state.copyWith(
        entries: [
          for (final entry in state.entries)
            if (entry.id != id) entry,
        ],
      ),
    );
  }

  /// Puts back whichever of the three built-in themes have been deleted, in
  /// their original order, leaving any that are still present untouched.
  ///
  /// The escape hatch for built-ins being ordinary, deletable entries. It
  /// restores what is *missing* rather than resetting everything, so it cannot
  /// undo edits to a built-in that is still there.
  Future<void> restoreBuiltIns() {
    final missing = state.missingSeededIds;
    if (missing.isEmpty) return Future.value();

    final seeded = ThemeLibraryState.seeded();
    return _persist(
      state.copyWith(
        entries: [
          ...state.entries,
          for (final id in missing) ?seeded.byId(id),
        ],
      ),
    );
  }

  Future<void> _update(
    String id,
    ThemeEntry Function(ThemeEntry) change, {
    bool write = true,
  }) {
    final existing = state.byId(id);
    if (existing == null) return Future.value();

    final next = change(existing);
    if (next == existing) return Future.value();

    // Mapped in place rather than removed and re-added: a theme must not jump
    // to the bottom of the list because one of its colours was changed.
    return _persist(
      state.copyWith(
        entries: [
          for (final entry in state.entries) entry.id == id ? next : entry,
        ],
      ),
      write: write,
    );
  }

  /// [write] false defers the disk write to the caller's next committing call,
  /// which is what a dragged colour slider relies on.
  Future<void> _persist(ThemeLibraryState next, {bool write = true}) async {
    // Set state first so the repaint is immediate; the write can lag a frame.
    state = next;
    if (!write) return;
    await ref
        .read(prefsProvider)
        .setString(_prefsKey, jsonEncode(next.toJson()));
  }
}

final themeLibraryProvider =
    NotifierProvider<ThemeLibrary, ThemeLibraryState>(ThemeLibrary.new);
