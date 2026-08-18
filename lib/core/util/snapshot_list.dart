// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// An immutable list with value equality.
///
/// The Matrix SDK hands out the *same* mutable `List<Room>` instance on every
/// call and re-sorts it in place, so a provider returning it would compare equal
/// to itself and never notify — the UI would simply never update.
///
/// Wrapping derived values in this type gives Riverpod something it can compare:
/// a sync that changed nothing the UI renders produces an equal snapshot, and
/// no widget rebuilds. That is what keeps a chatty homeserver from repainting
/// all three columns on every read receipt.
///
/// The element type must itself have value equality for this to work.
@immutable
class ListSnapshot<T> {
  const ListSnapshot(this.items);

  const ListSnapshot.empty() : items = const [];

  final List<T> items;

  int get length => items.length;
  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  T operator [](int index) => items[index];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListSnapshot<T> && listEquals(items, other.items);

  @override
  int get hashCode => Object.hashAll(items);

  @override
  String toString() => 'ListSnapshot(${items.length} items)';
}
