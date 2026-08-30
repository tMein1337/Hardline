// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/screen_sources.dart';

void main() {
  group('isShareableSource', () {
    // Monitors are few, named by index, and never junk. Filtering them would
    // only ever be a way to lose one.
    test('never filters a screen, whatever it is called', () {
      expect(
        isShareableSource(name: '', isWindow: false),
        isTrue,
      );
      expect(
        isShareableSource(
          name: 'Taskbar overflow window',
          isWindow: false,
          thumbnailWidth: 0,
          thumbnailHeight: 0,
        ),
        isTrue,
      );
    });

    test('drops a window with no title, which cannot be identified anyway', () {
      expect(isShareableSource(name: '', isWindow: true), isFalse);
      expect(isShareableSource(name: '   ', isWindow: true), isFalse);
    });

    // The reported case, on a German install. The English name is filtered by
    // the same list, which is the point of having the list rather than one
    // string.
    test('drops the taskbar overflow window in either language', () {
      expect(
        isShareableSource(
          name: 'Überlauffenster der Taskleiste',
          isWindow: true,
        ),
        isFalse,
      );
      expect(
        isShareableSource(name: 'Taskbar overflow window', isWindow: true),
        isFalse,
      );
    });

    test('matches denied titles regardless of case or surrounding space', () {
      expect(
        isShareableSource(name: '  PROGRAM MANAGER  ', isWindow: true),
        isFalse,
      );
    });

    test('drops a window whose thumbnail has no area to capture', () {
      expect(
        isShareableSource(
          name: 'Some tool window',
          isWindow: true,
          thumbnailWidth: 1,
          thumbnailHeight: 400,
        ),
        isFalse,
      );
      expect(
        isShareableSource(
          name: 'Some tool window',
          isWindow: true,
          thumbnailWidth: 0,
          thumbnailHeight: 0,
        ),
        isFalse,
      );
    });

    // A capturer that has not produced a thumbnail yet is telling us nothing,
    // and dropping a real window for being slow is worse than briefly showing
    // a dead one.
    test('keeps a window whose thumbnail has not arrived yet', () {
      expect(
        isShareableSource(name: 'Firefox', isWindow: true),
        isTrue,
      );
      expect(
        isShareableSource(
          name: 'Firefox',
          isWindow: true,
          thumbnailWidth: 320,
        ),
        isTrue,
      );
    });

    test('keeps an ordinary window', () {
      expect(
        isShareableSource(
          name: 'notes.md - Visual Studio Code',
          isWindow: true,
          thumbnailWidth: 320,
          thumbnailHeight: 180,
        ),
        isTrue,
      );
    });
  });

  group('numberedLabels', () {
    test('leaves a unique name exactly as it was', () {
      expect(
        numberedLabels(['Firefox', 'Screen 1']),
        ['Firefox', 'Screen 1'],
      );
    });

    test('numbers duplicates from 1, in list order', () {
      expect(
        numberedLabels(['Notepad', 'Notepad', 'Notepad']),
        ['Notepad 1', 'Notepad 2', 'Notepad 3'],
      );
    });

    test('numbers only the names that need it', () {
      expect(
        numberedLabels(['Notepad', 'Firefox', 'Notepad']),
        ['Notepad 1', 'Firefox', 'Notepad 2'],
      );
    });

    // The requirement is that the oldest share holds the lowest number *at any
    // time*, and the list is append-ordered — so recomputing after a removal
    // has to close the gap rather than leave "Notepad 2" alone on screen.
    test('renumbers after the oldest of a pair is stopped', () {
      final before = ['Notepad', 'Notepad', 'Notepad'];
      expect(numberedLabels(before), [
        'Notepad 1',
        'Notepad 2',
        'Notepad 3',
      ]);

      final after = ['Notepad', 'Notepad'];
      expect(numberedLabels(after), ['Notepad 1', 'Notepad 2']);
    });

    test('drops numbering entirely when only one of a name is left', () {
      expect(numberedLabels(['Notepad']), ['Notepad']);
    });

    test('handles an empty list', () {
      expect(numberedLabels([]), isEmpty);
    });

    test('keeps one entry per input, in the same order', () {
      final names = ['A', 'B', 'A', 'C', 'B', 'A'];
      final labels = numberedLabels(names);
      expect(labels, hasLength(names.length));
      expect(labels, ['A 1', 'B 1', 'A 2', 'C', 'B 2', 'A 3']);
    });
  });
}
