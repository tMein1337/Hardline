// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

/// Re-attaches a cached value as the first event of [source].
///
/// The Matrix SDK exposes its streams through `CachedStreamController`, which
/// keeps a `.value` but whose `.stream` is a bare `StreamController.broadcast()`
/// — it does **not** replay that value to new subscribers.
///
/// That matters because the SDK emits during `Client.init()`, before the widget
/// tree exists. A `StreamProvider` built directly on `.stream` would therefore
/// sit in `AsyncLoading` forever after a restored session: the app shows a
/// permanent splash screen while the client is fully synced behind it.
///
/// Every SDK stream surfaced to the UI must go through here:
///
/// ```dart
/// seededStream(client.onLoginStateChanged.stream, client.onLoginStateChanged.value)
/// ```
///
/// This takes the stream and value separately rather than being an extension on
/// `CachedStreamController` because that type is not exported from
/// `package:matrix/matrix.dart`, so its name cannot be written down without an
/// implementation import.
Stream<T> seededStream<T>(Stream<T> source, T? cached) {
  StreamSubscription<T>? subscription;
  late final StreamController<T> controller;

  controller = StreamController<T>(
    onListen: () {
      // Queued before the source is attached, so the cached value is always
      // delivered first.
      if (cached != null) controller.add(cached);
      subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    },
    onCancel: () async {
      await subscription?.cancel();
      subscription = null;
    },
  );

  return controller.stream;
}
