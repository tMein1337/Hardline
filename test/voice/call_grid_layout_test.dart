// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/call_grid_layout.dart';

void main() {
  group('chooseGrid', () {
    const wide = Size(1200, 700);
    const tall = Size(600, 1000);

    test('nothing to draw is an empty shape, not a crash', () {
      expect(chooseGrid(0, wide).isEmpty, isTrue);
      expect(chooseGrid(-1, wide).isEmpty, isTrue);
    });

    // A `LayoutBuilder` inside an unbounded parent hands out infinity, and a
    // collapsed one hands out zero. Both reach here before any tile is drawn.
    test('a degenerate box is an empty shape', () {
      expect(chooseGrid(4, const Size(double.infinity, 700)).isEmpty, isTrue);
      expect(chooseGrid(4, Size.zero).isEmpty, isTrue);
      expect(chooseGrid(4, const Size(1200, 0)).isEmpty, isTrue);
    });

    test('one tile takes the whole box, at the target aspect', () {
      final shape = chooseGrid(1, wide);

      expect(shape.columns, 1);
      expect(shape.rows, 1);
      expect(shape.tile.width / shape.tile.height, closeTo(16 / 9, 0.001));
      expect(shape.tile.width, lessThanOrEqualTo(wide.width));
      expect(shape.tile.height, lessThanOrEqualTo(wide.height));
    });

    // The whole reason this is a search rather than a formula: the answer
    // depends on the box's shape at least as much as on the count. Both of
    // these are three tiles.
    test('a very wide box lays tiles out in a row', () {
      expect(chooseGrid(3, const Size(1920, 500)).columns, 3);
    });

    test('a tall narrow box stacks them instead', () {
      expect(chooseGrid(3, tall).columns, 1);
    });

    // The case the gap tolerance exists for. Maximising tile area alone puts
    // nine tiles in two columns of five, three percent bigger and one cell
    // short — which reads as a broken grid rather than a slightly smaller one.
    test('nine tiles in a squarish box are three by three', () {
      final shape = chooseGrid(9, const Size(900, 900));

      expect(shape.columns, 3);
      expect(shape.rows, 3);
    });

    test('four tiles in a squarish box are two by two', () {
      final shape = chooseGrid(4, const Size(900, 900));

      expect(shape.columns, 2);
      expect(shape.rows, 2);
    });

    // Tidiness only wins when it is nearly free. Five tiles cannot be arranged
    // without a gap at all, so the largest tile has to win outright.
    test('a shape that is merely tidy does not beat a much larger one', () {
      final shape = chooseGrid(5, const Size(1200, 700));

      expect(shape.columns * shape.rows, greaterThanOrEqualTo(5));
      expect(shape.tile.width, greaterThan(chooseGrid(9, const Size(1200, 700)).tile.width));
    });

    test('every tile fits inside the box it was given', () {
      for (var count = 1; count <= 16; count++) {
        for (final area in [wide, tall, const Size(900, 900)]) {
          final shape = chooseGrid(count, area, spacing: 8);

          final usedWidth =
              shape.tile.width * shape.columns + 8 * (shape.columns - 1);
          final usedHeight =
              shape.tile.height * shape.rows + 8 * (shape.rows - 1);

          expect(
            usedWidth,
            lessThanOrEqualTo(area.width + 0.001),
            reason: '$count tiles in $area overflowed horizontally',
          );
          expect(
            usedHeight,
            lessThanOrEqualTo(area.height + 0.001),
            reason: '$count tiles in $area overflowed vertically',
          );
        }
      }
    });

    test('the arrangement always has room for every tile', () {
      for (var count = 1; count <= 16; count++) {
        for (final area in [wide, tall, const Size(900, 900)]) {
          final shape = chooseGrid(count, area);
          expect(
            shape.columns * shape.rows,
            greaterThanOrEqualTo(count),
            reason:
                '$count tiles did not fit in ${shape.columns}x${shape.rows}',
          );
        }
      }
    });

    test('tiles keep the target aspect whatever the count', () {
      for (var count = 1; count <= 16; count++) {
        final shape = chooseGrid(count, wide);
        expect(shape.tile.width / shape.tile.height, closeTo(16 / 9, 0.001));
      }
    });

    test('a different aspect is honoured', () {
      final shape = chooseGrid(4, wide, aspect: 1);

      expect(shape.tile.width, closeTo(shape.tile.height, 0.001));
    });

    test('spacing is taken out of the box, not added to it', () {
      final tight = chooseGrid(4, wide, spacing: 0);
      final loose = chooseGrid(4, wide, spacing: 24);

      expect(loose.tile.width, lessThan(tight.tile.width));
    });
  });
}
