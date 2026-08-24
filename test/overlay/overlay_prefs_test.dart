// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/overlay/overlay_layout.dart';
import 'package:hardline/features/overlay/overlay_prefs_state.dart';

void main() {
  OverlayPrefsState roundTrip(OverlayPrefsState state) =>
      OverlayPrefsState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>,
      );

  group('OverlayPrefsState', () {
    test('round-trips through JSON', () {
      const state = OverlayPrefsState(
        enabled: true,
        monitorId: r'\\.\DISPLAY2',
        excludeFromCapture: false,
        layouts: [
          OverlayLayout(id: 'a', name: 'Gaming', x: 0.5, y: 0.25),
          OverlayLayout(id: 'b', name: 'Wide', horizontal: true),
        ],
        assignments: {'javaw.exe': 'a', 'cs2.exe': 'a'},
        defaultLayoutId: 'b',
        toggleHotkey: OverlayHotkey(modifiers: 2, key: 0x4F),
        editHotkey: OverlayHotkey(modifiers: 6, key: 0x70),
      );

      expect(roundTrip(state), state);
    });

    test('malformed JSON degrades to defaults instead of throwing', () {
      final state = OverlayPrefsState.fromJson(const {
        'layouts': 'not a list',
        'assignments': 42,
        'toggleHotkey': 'nonsense',
      });

      expect(state.layouts, hasLength(1));
      expect(state.assignments, isEmpty);
      expect(state.enabled, isFalse);
    });

    // The overlay must always have somewhere to draw. A file that lost its
    // layouts should come back with one, not with a feature that silently
    // refuses to appear.
    test('a file with no layouts still yields one', () {
      final state = OverlayPrefsState.fromJson(const {'layouts': <Object?>[]});

      expect(state.layouts, hasLength(1));
      expect(state.layoutFor('anything.exe'), state.layouts.single);
    });

    test('an out-of-range position is clamped rather than rejected', () {
      final layout = OverlayLayout.fromJson(const {
        'id': 'a',
        'name': 'A',
        'x': 4.0,
        'y': -2.0,
        'avatarSize': 100000.0,
      });

      expect(layout.x, 1);
      expect(layout.y, 0);
      expect(layout.avatarSize, kMaxOverlayAvatar);
    });
  });

  group('layout resolution', () {
    const prefs = OverlayPrefsState(
      layouts: [
        OverlayLayout(id: 'gaming', name: 'Gaming'),
        OverlayLayout(id: 'plain', name: 'Plain'),
      ],
      assignments: {'javaw.exe': 'gaming', 'cs2.exe': 'gaming'},
      defaultLayoutId: 'plain',
    );

    // The whole point of layouts having names and ids: a HUD is not owned by
    // one game, and a second game can adopt it rather than have one rebuilt.
    test('two games can share one layout', () {
      expect(prefs.layoutFor('javaw.exe').id, 'gaming');
      expect(prefs.layoutFor('cs2.exe').id, 'gaming');
      expect(prefs.executablesFor('gaming'), ['cs2.exe', 'javaw.exe']);
    });

    test('anything unassigned gets the default', () {
      expect(prefs.layoutFor('chrome.exe').id, 'plain');
      expect(prefs.layoutFor('').id, 'plain');
    });

    test('assignment lookup ignores case', () {
      expect(prefs.layoutFor('JavaW.EXE').id, 'gaming');
    });

    // A dangling id would leave the overlay with nothing to draw. Falling back
    // is what makes `layoutFor` total.
    test('an assignment to a deleted layout falls back', () {
      const broken = OverlayPrefsState(
        layouts: [OverlayLayout(id: 'plain', name: 'Plain')],
        assignments: {'javaw.exe': 'gone'},
        defaultLayoutId: 'plain',
      );

      expect(broken.layoutFor('javaw.exe').id, 'plain');
    });

    test('a dangling assignment is not even read back from disk', () {
      final state = OverlayPrefsState.fromJson(const {
        'layouts': [
          {'id': 'plain', 'name': 'Plain'},
        ],
        'assignments': {'javaw.exe': 'gone'},
        'defaultLayoutId': 'plain',
      });

      expect(state.assignments, isEmpty);
    });

    test('a default pointing at nothing falls back to a real layout', () {
      final state = OverlayPrefsState.fromJson(const {
        'layouts': [
          {'id': 'plain', 'name': 'Plain'},
        ],
        'defaultLayoutId': 'gone',
      });

      expect(state.defaultLayoutId, 'plain');
    });
  });
}
