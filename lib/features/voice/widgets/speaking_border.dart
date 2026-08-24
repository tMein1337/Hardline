// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';
import 'speaking_ring.dart';
import 'speaking_watch.dart';

/// Lights a call tile while the person it belongs to is speaking.
///
/// The rectangular counterpart of [SpeakingRing]. A tile showing video has no
/// avatar to ring, so the tile's own edge carries the signal instead — same
/// colour, same fade, so the grid and the sidebar say the same thing the same
/// way.
///
/// Like the ring, the width is reserved whether or not it is lit: a border that
/// appeared by growing would nudge the video inside it every time somebody drew
/// breath, and on a texture that means a resize rather than a repaint.
class SpeakingBorder extends StatelessWidget {
  const SpeakingBorder({
    super.key,
    required this.userId,
    required this.radius,
    required this.child,
    this.roomId,
  });

  final String userId;

  /// The tile's corner radius. The border sits outside it, so its own radius is
  /// this plus the border width — the same concentricity rule the ring follows.
  final double radius;

  /// Which room's call to look at; see [SpeakingWatch.roomId].
  final String? roomId;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SpeakingWatch(
      userId: userId,
      roomId: roomId,
      builder: (context, isSpeaking) => AnimatedContainer(
        duration: kSpeakingFade,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius + kSpeakingRingWidth),
          border: Border.all(
            color: isSpeaking
                ? context.colors.voiceSpeakingRing
                : Colors.transparent,
            width: kSpeakingRingWidth,
          ),
        ),
        child: child,
      ),
    );
  }
}
