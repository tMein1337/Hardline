import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../spaces/space_summary.dart';

/// Which space (Discord "server") the rail has selected.
class SelectedSpaceId extends Notifier<String> {
  @override
  String build() => kHomeSpaceId;

  void select(String spaceId) => state = spaceId;
}

final selectedSpaceIdProvider = NotifierProvider<SelectedSpaceId, String>(
  SelectedSpaceId.new,
);

/// Remembers the open room per space, so switching away and back returns to
/// where you were — as Discord does.
class SelectedRoomIds extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void select({required String spaceId, required String roomId}) =>
      state = {...state, spaceId: roomId};

  /// Called when a room disappears (left, or removed from the space).
  void clear(String spaceId) => state = {...state}..remove(spaceId);
}

final selectedRoomIdsProvider =
    NotifierProvider<SelectedRoomIds, Map<String, String>>(
      SelectedRoomIds.new,
    );

/// The room currently open, or null if none is selected in this space.
final selectedRoomIdProvider = Provider<String?>((ref) {
  final spaceId = ref.watch(selectedSpaceIdProvider);
  return ref.watch(selectedRoomIdsProvider)[spaceId];
});
