// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../providers/injected_providers.dart';

/// Cache key for a resolved avatar thumbnail.
@immutable
class AvatarRequest {
  const AvatarRequest({required this.mxcUri, required this.size});

  final String mxcUri;

  /// Requested edge length in logical pixels.
  final int size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvatarRequest && mxcUri == other.mxcUri && size == other.size;

  @override
  int get hashCode => Object.hash(mxcUri, size);
}

/// Resolves an `mxc://` URI to a fetchable thumbnail URL.
///
/// Async because the SDK has to determine whether the homeserver supports
/// authenticated media before it knows which endpoint to use. The modern
/// endpoint requires an `Authorization` header — see [mediaRequestHeaders].
///
/// Results are cached by [AvatarRequest], so the same avatar appearing in the
/// rail, the room list and a message is resolved once.
final avatarUriProvider = FutureProvider.family<Uri?, AvatarRequest>((
  ref,
  request,
) async {
  final client = ref.watch(clientProvider);
  try {
    return await Uri.parse(request.mxcUri).getThumbnailUri(
      client,
      width: request.size,
      height: request.size,
      method: ThumbnailMethod.crop,
    );
  } catch (error) {
    // A malformed mxc uri or an unreachable server just means we fall back to
    // initials; it is not worth failing a whole list over.
    debugPrint('Could not resolve avatar ${request.mxcUri}: $error');
    return null;
  }
});

/// Authenticated media (Matrix 1.11+) rejects unauthenticated requests, so
/// every media fetch must carry the access token — avatars and message
/// attachments alike.
final mediaRequestHeaders = Provider<Map<String, String>>((ref) {
  final token = ref.watch(clientProvider).accessToken;
  return token == null ? const {} : {'authorization': 'Bearer $token'};
});
