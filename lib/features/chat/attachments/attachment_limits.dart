import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';

/// The homeserver's `m.upload.size`, or null if it does not advertise one.
///
/// `getConfig()` is cached in the SDK's database for three days, so watching
/// this is cheap. The limit is checked when an attachment is *staged* rather
/// than when it is sent, so the tray refuses a 2 GB file immediately instead of
/// after the user has typed a caption and pressed Enter.
///
/// `Room.sendFileEvent` re-checks and throws `FileTooBigMatrixException`
/// anyway (room.dart:996-1001); this exists purely so the refusal is early and
/// legible.
final maxUploadSizeProvider = FutureProvider<int?>((ref) async {
  try {
    final config = await ref.watch(clientProvider).getConfig();
    return config.mUploadSize;
  } catch (error) {
    // An unknown limit is not a reason to block uploads — let the server
    // decide, which is exactly what the SDK does when this call fails.
    debugPrint('Could not read the media config: $error');
    return null;
  }
});
