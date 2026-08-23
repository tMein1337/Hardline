// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../call_controller_provider.dart';
import '../speaking_participants.dart';

/// How thick the ring is, and how much bigger it makes an avatar.
///
/// The space is reserved whether or not anybody is talking — the ring appears
/// by gaining a colour, never by gaining a size. A ring that changed the
/// layout would shove every name in the sidebar sideways each time somebody
/// drew breath.
const _ringWidth = 2.0;

/// Lights an avatar while the person behind it is speaking.
///
/// Wraps rather than replaces [MxAvatar], so the avatar keeps knowing nothing
/// about calls, and so the same ring works on the participant list, the user
/// footer, and anywhere else a face is drawn.
///
/// The whole design constraint is that this is cheap. LiveKit reports speakers
/// several times a second, the sidebar can hold a dozen of these, and the room
/// list is built around not repainting. So each ring listens on its own and
/// rebuilds **only when its own person starts or stops** — somebody else taking
/// over the conversation is not a rebuild here.
class SpeakingRing extends ConsumerStatefulWidget {
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

  /// Which room's call to look at.
  ///
  /// Null means "whichever call this client is in", which is what the user
  /// footer wants — it is not tied to a room, and the only thing it is asking
  /// is whether the microphone is picking *you* up. The participant list passes
  /// its channel, so that somebody in two calls at once is only ringed under
  /// the one we can actually hear.
  final String? roomId;

  final Widget child;

  @override
  ConsumerState<SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends ConsumerState<SpeakingRing> {
  ValueListenable<SpeakingParticipants>? _speaking;
  bool _isSpeaking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenTo(ref.watch(speakingParticipantsProvider));
  }

  @override
  void didUpdateWidget(SpeakingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The row was recycled onto a different person or channel; the answer for
    // the old one says nothing about the new one.
    if (oldWidget.userId != widget.userId ||
        oldWidget.roomId != widget.roomId) {
      _read();
    }
  }

  @override
  void dispose() {
    _speaking?.removeListener(_read);
    super.dispose();
  }

  void _listenTo(ValueListenable<SpeakingParticipants> speaking) {
    if (identical(_speaking, speaking)) return;
    _speaking?.removeListener(_read);
    _speaking = speaking..addListener(_read);
    _isSpeaking = _currentlySpeaking;
  }

  bool get _currentlySpeaking =>
      _speaking?.value.contains(widget.userId, inRoom: widget.roomId) ?? false;

  /// The reason this class is stateful at all.
  ///
  /// A `ValueListenableBuilder` would rebuild on every speaker report, for
  /// every avatar on screen, however little the answer changed. This asks the
  /// one question it cares about and stays put unless the answer moved.
  void _read() {
    final speaking = _currentlySpeaking;
    if (speaking == _isSpeaking || !mounted) return;
    setState(() => _isSpeaking = speaking);
  }

  @override
  Widget build(BuildContext context) {
    // Avatars are rounded squares, not circles, so the ring is one too — and
    // its radius is the avatar's plus the ring's width, or the corners drift
    // apart and it reads as a badly drawn box rather than an outline.
    final inner = widget.size * kAvatarRadiusFraction;

    return AnimatedContainer(
      // Short enough to feel immediate, long enough that a sentence with a
      // pause in it does not strobe.
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(inner + _ringWidth),
        border: Border.all(
          color: _isSpeaking
              ? context.colors.voiceSpeakingRing
              : Colors.transparent,
          width: _ringWidth,
        ),
      ),
      child: widget.child,
    );
  }
}
