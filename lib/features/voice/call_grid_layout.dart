// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How a given number of equal tiles is arranged in a given box.
@immutable
class GridShape {
  const GridShape({
    required this.columns,
    required this.rows,
    required this.tile,
  });

  /// Nothing to draw.
  const GridShape.empty() : columns = 0, rows = 0, tile = Size.zero;

  final int columns;
  final int rows;

  /// The size of one cell, already at the target aspect ratio.
  ///
  /// Cells are letterboxed inside their share of the box rather than stretched
  /// to fill it, so a video is never distorted and the grid stays regular.
  final Size tile;

  bool get isEmpty => columns == 0 || rows == 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridShape &&
          columns == other.columns &&
          rows == other.rows &&
          tile == other.tile;

  @override
  int get hashCode => Object.hash(columns, rows, tile);

  @override
  String toString() => 'GridShape(${columns}x$rows, $tile)';
}

/// How much smaller than the best a tile may be and still be preferred for
/// leaving no empty cell.
///
/// Maximising tile area alone is *almost* right, and wrong in one visible way:
/// for nine tiles in a squarish column it picks two columns of five over three
/// rows of three, because those tiles come out about a tenth larger in area —
/// five percent on an edge. Five percent is invisible. A tenth cell sitting
/// empty at the bottom of a two-wide column is not; it reads as a grid that has
/// gone wrong rather than one that is slightly smaller.
///
/// A tenth is wide enough to catch that family of cases and narrow enough that
/// a genuinely better shape still wins outright. It only ever decides between
/// arrangements that differ in *emptiness* — five tiles leave a gap however
/// they are arranged, so there the largest tile still takes it.
const _gapTolerance = 0.9;

/// Picks the arrangement that makes the tiles as large as possible.
///
/// Every column count from 1 to [tileCount] is tried and scored. That is cheap
/// — a call has tens of tiles, not thousands — and it is the only approach that
/// gets the awkward counts right: the answer depends on the box's shape as much
/// as on the number of tiles, and there is no closed form that respects both.
///
/// Every tile is the same size, deliberately. It is what makes "somebody
/// sharing a camera and two screens takes the space of three people" true
/// without any special-casing: they simply occupy three cells.
///
/// Two criteria, in order: no empty cells, then the largest tile — but the
/// first only overrules the second within [_gapTolerance]. Ties break towards
/// fewer columns, which keeps the arrangement from flipping between two equally
/// good shapes as the window is dragged.
GridShape chooseGrid(
  int tileCount,
  Size area, {
  double aspect = 16 / 9,
  double spacing = 8,
}) {
  if (tileCount <= 0) return const GridShape.empty();
  if (!area.width.isFinite ||
      !area.height.isFinite ||
      area.width <= 0 ||
      area.height <= 0) {
    return const GridShape.empty();
  }

  final candidates = <({GridShape shape, double area, int empty})>[];

  for (var columns = 1; columns <= tileCount; columns++) {
    final rows = (tileCount / columns).ceil();

    final cellWidth = (area.width - spacing * (columns - 1)) / columns;
    final cellHeight = (area.height - spacing * (rows - 1)) / rows;
    if (cellWidth <= 0 || cellHeight <= 0) continue;

    // Letterbox the aspect into the cell: whichever of the two dimensions runs
    // out first is the one that decides the size.
    final width = cellWidth / cellHeight > aspect
        ? cellHeight * aspect
        : cellWidth;
    final height = width / aspect;

    candidates.add((
      shape: GridShape(
        columns: columns,
        rows: rows,
        tile: Size(width, height),
      ),
      area: width * height,
      empty: columns * rows - tileCount,
    ));
  }

  if (candidates.isEmpty) return const GridShape.empty();

  final largest = candidates
      .map((candidate) => candidate.area)
      .reduce((a, b) => a > b ? a : b);

  // Only shapes close enough to the largest are allowed to compete on
  // tidiness; a shape that is merely tidy and much smaller is not a better
  // answer, it is a smaller one.
  final viable = candidates
      .where((candidate) => candidate.area >= largest * _gapTolerance)
      .toList();

  var best = viable.first;
  for (final candidate in viable.skip(1)) {
    if (candidate.empty < best.empty) {
      best = candidate;
    } else if (candidate.empty == best.empty && candidate.area > best.area) {
      best = candidate;
    }
  }

  return best.shape;
}
