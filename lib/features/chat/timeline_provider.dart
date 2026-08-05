import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import 'timeline_controller.dart';

/// Per-room timeline, disposed when the room is closed.
///
/// A plain `Provider` with an explicit `ref.onDispose` rather than
/// `ChangeNotifierProvider`, which Riverpod 3 moved to `legacy.dart`.
///
/// The provider body is synchronous on purpose: `ref.onDispose` is registered
/// before anything awaits, so it can never run against an already-disposed ref.
/// The async part happens in `start()`, which guards its own completion.
final timelineControllerProvider = Provider.family<TimelineController, String>(
  (ref, roomId) {
    final controller = TimelineController(
      client: ref.watch(clientProvider),
      roomId: roomId,
    );

    ref.onDispose(controller.dispose);
    unawaited(controller.start());

    return controller;
  },
  // Switching rooms tears the old controller down, which is what fires
  // Timeline.cancelSubscriptions().
  isAutoDispose: true,
);
