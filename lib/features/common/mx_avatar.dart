// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/matrix/avatar_uri_provider.dart';
import '../../core/util/initials.dart';
import '../../theme/theme_context.dart';

/// Corner radius as a fraction of the avatar's edge, used when a caller does
/// not name one. Rounded squares, not circles: it is the shape the space rail,
/// the room list and the attachment cards all share, and the one thing that
/// most decides the interface's silhouette.
const _radiusFraction = 0.28;

/// An avatar for a room, space or user.
///
/// Falls back to initials on a deterministic color whenever there is no avatar,
/// the URL cannot be resolved, or the image fails to load — the last of which
/// matters because authenticated media returns 401 for an unauthenticated
/// request, and a broken-image icon in every row would look like a crash.
class MxAvatar extends ConsumerWidget {
  const MxAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.mxcUri,
    this.size = 40,
    this.borderRadius,
  });

  /// Used for the initials fallback.
  final String name;

  /// Stable input for the fallback color — a user or room id, so the same
  /// entity always gets the same color.
  final String seed;

  final String? mxcUri;
  final double size;

  /// Defaults to a rounded square of [_radiusFraction]. Callers override it
  /// only where a different shape is part of the surrounding design.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius =
        borderRadius ?? BorderRadius.circular(size * _radiusFraction);
    final fallback = _Fallback(
      name: name,
      seed: seed,
      size: size,
      borderRadius: radius,
    );

    final mxc = mxcUri;
    if (mxc == null || mxc.isEmpty) return fallback;

    final resolved = ref.watch(
      avatarUriProvider(
        AvatarRequest(mxcUri: mxc, size: _pixelSize(context)),
      ),
    );

    return resolved.maybeWhen(
      data: (uri) {
        if (uri == null) return fallback;
        return ClipRRect(
          borderRadius: radius,
          child: Image.network(
            uri.toString(),
            width: size,
            height: size,
            fit: BoxFit.cover,
            headers: ref.watch(mediaRequestHeaders),
            errorBuilder: (_, _, _) => fallback,
            // Avoids a flash of fallback on every rebuild once cached.
            gaplessPlayback: true,
          ),
        );
      },
      orElse: () => fallback,
    );
  }

  /// Request the thumbnail at device resolution so it is not blurry on a
  /// high-DPI display.
  int _pixelSize(BuildContext context) =>
      (size * MediaQuery.devicePixelRatioOf(context)).round();
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.name,
    required this.seed,
    required this.size,
    required this.borderRadius,
  });

  final String name;
  final String seed;
  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.avatarColorFor(seed),
        borderRadius: borderRadius,
      ),
      alignment: Alignment.center,
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: colors.textOnAccent,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}
