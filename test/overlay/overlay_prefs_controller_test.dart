// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/overlay/overlay_layout.dart';
import 'package:hardline/features/overlay/overlay_prefs_controller.dart';
import 'package:hardline/features/overlay/overlay_prefs_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
  });

  OverlayPrefsState state() => container.read(overlayPrefsProvider);
  OverlayPrefsController notifier() =>
      container.read(overlayPrefsProvider.notifier);

  group('a duplicated layout', () {
    // Every setting, and the talking opacity used not to come along: a copy
    // of a layout set to half came out at full.
    test('carries every setting of the one it was made from', () {
      const original = OverlayLayout(
        id: kDefaultOverlayLayoutId,
        name: 'Default',
        x: 0.4,
        y: 0.6,
        horizontal: true,
        avatarSize: 64,
        showNames: false,
        idleOpacity: 0.2,
        activeOpacity: 0.5,
      );
      notifier().updateLayout(original);

      final copy = notifier().addLayout('Copy', copyOf: original);

      expect(copy.id, isNot(original.id));
      expect(copy.name, 'Copy');
      expect(copy.x, 0.4);
      expect(copy.y, 0.6);
      expect(copy.horizontal, isTrue);
      expect(copy.avatarSize, 64);
      expect(copy.showNames, isFalse);
      expect(copy.idleOpacity, 0.2);
      expect(copy.activeOpacity, 0.5);
    });
  });

  // Layouts are named things, not properties of a game.
  group('one layout, several games', () {
    test('editing it changes it for every game that uses it', () {
      final shared = notifier().addLayout('Shared');
      notifier().assign('javaw.exe', shared.id);
      notifier().assign('CS2.exe', shared.id);

      notifier().updateLayout(shared.copyWith(x: 0.75));

      expect(state().layoutFor('javaw.exe').x, 0.75);
      expect(state().layoutFor('cs2.exe').x, 0.75);
      // And not for anything else.
      expect(state().layoutFor('notepad.exe').x, isNot(0.75));
    });
  });

  group('deleting a layout', () {
    test('sends the games that used it back to the default', () {
      final doomed = notifier().addLayout('Doomed');
      notifier().assign('javaw.exe', doomed.id);
      notifier().assign('cs2.exe', doomed.id);

      notifier().removeLayout(doomed.id);

      expect(state().assignments, isEmpty);
      expect(state().layoutFor('javaw.exe').id, kDefaultOverlayLayoutId);
      expect(state().layoutFor('cs2.exe').id, kDefaultOverlayLayoutId);
    });

    // Otherwise everything unassigned would point at nothing.
    test('moves the default when the default is the one deleted', () {
      final other = notifier().addLayout('Other');

      notifier().removeLayout(kDefaultOverlayLayoutId);

      expect(state().defaultLayoutId, other.id);
      expect(state().layoutFor('anything.exe').id, other.id);
    });

    // The overlay must always have somewhere to draw.
    test('refuses to delete the last one', () {
      notifier().removeLayout(kDefaultOverlayLayoutId);
      expect(state().layouts, hasLength(1));
    });

    test('survives a restart', () {
      final doomed = notifier().addLayout('Doomed');
      notifier().assign('javaw.exe', doomed.id);
      notifier().removeLayout(doomed.id);

      final stored =
          jsonDecode(prefs.getString('overlay_prefs_v1')!)
              as Map<String, Object?>;
      final reloaded = OverlayPrefsState.fromJson(stored);
      expect(reloaded.layouts, hasLength(1));
      expect(reloaded.assignments, isEmpty);
    });
  });

  // A dragged position is written as it is dropped, and is
  // there again after a restart.
  test('a dragged position is stored and read back', () {
    notifier().updateLayout(state().layouts.single.copyWith(x: 0.3, y: 0.7));

    final reloaded = OverlayPrefsState.fromJson(
      jsonDecode(prefs.getString('overlay_prefs_v1')!) as Map<String, Object?>,
    );
    expect(reloaded.layouts.single.x, 0.3);
    expect(reloaded.layouts.single.y, 0.7);
  });
}
