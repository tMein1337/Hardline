// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import 'speaking_watch.dart';

/// How thick the ring is, and how much bigger it makes an avatar.
///
/// The space is reserved whether or not anybody is talking — the ring appears
/// by gaining a colour, never by gaining a size. A ring that changed the
/// layout would shove every name in the sidebar sideways each time somebody
/// drew breath.
const kSpeakingRingWidth = 2.0;

/// How long the ring takes to come up and go out.
///
/// Short enough to feel immediate, long enough that a sentence with a pause in
/// it does not strobe. Shared with the tile border so the two agree.
const kSpeakingFade = Duration(milliseconds: 120);

/// Lights an avatar while the person behind it is speaking.
///
/// Wraps rather than replaces [MxAvatar], so the avatar keeps knowing nothing
/// about calls, and so the same ring works on the participant list, the user
/// footer, the call grid, and anywhere else a face is drawn.
///
/// The rebuild discipline this depends on lives in [SpeakingWatch]; see there
/// for why it is not a `ValueListenableBuilder`.
class SpeakingRing extends StatelessWidget {
  const SpeakingRing({
    super.key,
    required this.userId,
    required this.size,
    required this.child,
    this.roomId,
  });

  final String userId;

  /// The avatar's edge, used to keep the ring's corners concentric with it.
  final double size;

  /// Which room's call to look at; see [SpeakingWatch.roomId].
  final String? roomId;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Avatars are rounded squares, not circles, so the ring is one too — and
    // its radius is the avatar's plus the ring's width, or the corners drift
    // apart and it reads as a badly drawn box rather than an outline.
    final inner = size * kAvatarRadiusFraction;

    return SpeakingWatch(
      userId: userId,
      roomId: roomId,
      builder: (context, isSpeaking) => AnimatedContainer(
        duration: kSpeakingFade,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(inner + kSpeakingRingWidth),
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
