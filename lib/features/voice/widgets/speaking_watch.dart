// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../call_controller_provider.dart';
import '../speaking_participants.dart';

/// Rebuilds its [builder] when one particular person starts or stops talking.
///
/// The whole design constraint is that this is cheap. Levels are measured ten
/// times a second, the sidebar can hold a dozen of these and the call grid
/// another dozen, and both are built around not repainting. So each watcher
/// asks the one question it cares about and stays put unless *its own* answer
/// moved — somebody else taking over the conversation is not a rebuild here.
///
/// That is also why this is a `ConsumerStatefulWidget` hooking the listenable
/// by hand rather than a `ValueListenableBuilder`: the latter rebuilds on every
/// speaker report, for every avatar on screen, however little the answer
/// changed.
///
/// Extracted from `SpeakingRing`, which was the only thing that needed it until
/// video tiles wanted the same behaviour with a different shape. The discipline
/// is subtle enough that having two copies of it would mean having one correct
/// copy and one that drifted.
class SpeakingWatch extends ConsumerStatefulWidget {
  const SpeakingWatch({
    super.key,
    required this.userId,
    required this.builder,
    this.roomId,
  });

  final String userId;

  /// Which room's call to look at.
  ///
  /// Null means "whichever call this client is in", which is what the user
  /// footer wants — it is not tied to a room, and the only thing it is asking
  /// is whether the microphone is picking *you* up. The participant list passes
  /// its channel, so that somebody in two calls at once is only lit under the
  /// one we can actually hear.
  final String? roomId;

  /// Called with whether [userId] is audible, and nothing else.
  ///
  /// Anything expensive should be built outside and passed in as a captured
  /// child: a widget instance that does not change is not rebuilt, which is
  /// what keeps a lit ring from repainting the avatar inside it.
  final Widget Function(BuildContext context, bool isSpeaking) builder;

  @override
  ConsumerState<SpeakingWatch> createState() => _SpeakingWatchState();
}

class _SpeakingWatchState extends ConsumerState<SpeakingWatch> {
  ValueListenable<SpeakingParticipants>? _speaking;
  bool _isSpeaking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenTo(ref.watch(speakingParticipantsProvider));
  }

  @override
  void didUpdateWidget(SpeakingWatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The row or tile was recycled onto a different person or channel; the
    // answer for the old one says nothing about the new one.
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

  void _read() {
    final speaking = _currentlySpeaking;
    if (speaking == _isSpeaking || !mounted) return;
    setState(() => _isSpeaking = speaking);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _isSpeaking);
}
