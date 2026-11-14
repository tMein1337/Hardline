// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The shape of the spaces this account is in, and how much of it to show.
///
/// A space can contain a space. The rail used to be flat, so joining one from
/// inside another put it at the bottom of the column as a sibling of the space
/// it had come out of — honest about what had been joined and silent about
/// where it belonged.
///
/// The decision this file makes: **the rail nests, and shows one branch at a
/// time.** Spaces that sit inside no other joined space are always there. A
/// space's own sub-spaces appear directly beneath it, set in, while that space
/// or anything inside it is the one selected — and fold away again when the
/// selection moves elsewhere.
///
/// Showing every level always was the alternative, and it does not survive
/// contact with a rail 64 pixels wide: the whole point of the column is to be
/// a short list of places, and a community with a dozen sub-spaces would push
/// every other space off the screen for somebody who was not even in it at the
/// time. Never showing them — reaching a sub-space only through its parent's
/// overview — is how it worked before, and loses the place the moment the
/// overview is replaced by a room.
///
/// Pure, and over plain ids: the caller reads the SDK, this decides.
library;

/// One space as the rail draws it.
class SpaceBranch {
  const SpaceBranch({
    required this.id,
    required this.depth,
    required this.parentId,
    required this.folded,
  });

  final String id;

  /// How far in: 0 for a space inside no other, 1 for one of its sub-spaces.
  final int depth;

  /// The space this one is drawn beneath, or null at the top.
  final String? parentId;

  /// Sub-spaces of this one that exist and are not being shown.
  ///
  /// Everything beneath them counts too. These are what the rail entry stands
  /// in for while it is folded, so their unread counts belong on its badge —
  /// a mention in a sub-space nobody can see is a mention nobody will read.
  final List<String> folded;
}

/// The rail's spaces, in the order and at the depth they are drawn.
///
/// [spaces] is every joined space, in the SDK's order, which is the order the
/// flat rail used and the one kept for anything at the same level.
/// [childrenOf] gives, for a space, the *spaces* it lists that this account
/// has also joined, in the parent's own order. [selectedId] is the rail's
/// selection, and need not be a space at all.
///
/// Two shapes Matrix permits and a tree does not:
///
///  * **A space in several spaces** is drawn once, beneath the first parent
///    that reaches it. Listing it under each would give one place two entries
///    with one selection between them.
///  * **A loop** — A lists B, B lists A — has no top. Nothing forbids one and
///    it takes two people a minute to make. Whichever of the pair comes first
///    in [spaces] is treated as the top, so both still appear; without that,
///    each would be waiting to be drawn beneath the other and the rail would
///    show neither.
List<SpaceBranch> railBranches({
  required List<String> spaces,
  required Map<String, List<String>> childrenOf,
  required String selectedId,
}) {
  final joined = spaces.toSet();
  List<String> subSpaces(String id) => [
    for (final child in childrenOf[id] ?? const <String>[])
      if (child != id && joined.contains(child)) child,
  ];

  // A space is at the top unless some *other* joined space lists it.
  final claimed = <String>{for (final id in spaces) ...subSpaces(id)};
  final roots = [
    for (final id in spaces)
      if (!claimed.contains(id)) id,
  ];

  // Anything a walk from those does not reach is in a loop with no way in.
  // Promote the earliest member of each such loop until nothing is left over.
  final reachable = <String>{};
  void reach(String id) {
    if (!reachable.add(id)) return;
    subSpaces(id).forEach(reach);
  }

  roots.forEach(reach);
  for (final id in spaces) {
    if (reachable.contains(id)) continue;
    roots.add(id);
    reach(id);
  }
  // Promoted ones were appended; put everything back in the rail's own order
  // so a loop does not send a space to the bottom of the column.
  final position = {for (final (index, id) in spaces.indexed) id: index};
  roots.sort((a, b) => position[a]!.compareTo(position[b]!));

  // Each space belongs to the first parent that reaches it, depth first.
  final parentOf = <String, String?>{};
  void assign(String id, String? parent) {
    if (parentOf.containsKey(id)) return;
    parentOf[id] = parent;
    for (final child in subSpaces(id)) {
      assign(child, id);
    }
  }

  for (final root in roots) {
    assign(root, null);
  }

  // The branch that is open: the selection and everything above it.
  final open = <String>{};
  for (
    String? id = selectedId;
    id != null && parentOf.containsKey(id) && open.add(id);
    id = parentOf[id]
  ) {}

  List<String> ownChildren(String id) => [
    for (final child in subSpaces(id))
      if (parentOf[child] == id) child,
  ];

  List<String> everythingUnder(String id) => [
    for (final child in ownChildren(id)) ...[child, ...everythingUnder(child)],
  ];

  final branches = <SpaceBranch>[];
  void emit(String id, int depth) {
    final isOpen = open.contains(id);
    branches.add(
      SpaceBranch(
        id: id,
        depth: depth,
        parentId: parentOf[id],
        folded: isOpen ? const [] : everythingUnder(id),
      ),
    );
    if (!isOpen) return;
    for (final child in ownChildren(id)) {
      emit(child, depth + 1);
    }
  }

  for (final root in roots) {
    emit(root, 0);
  }
  return branches;
}
