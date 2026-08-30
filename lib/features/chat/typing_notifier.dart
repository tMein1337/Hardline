// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Tells the room you are typing, and stops telling it.
///
/// Nothing in this app sent a typing notification before. The receiving half
/// existed — the activity page draws a "typing…" badge for people you follow —
/// so the feature looked half-broken from one side and entirely broken from
/// the other: nobody ever saw *your* badge, and you only ever saw the badge of
/// somebody you had followed who was using a different client.
///
/// **Rate is the whole design.** A notification is an HTTP request, and the
/// composer's `onChanged` fires on every keystroke. So:
///
///  * a `true` is sent at most once per [_resend], and only when the state has
///    actually changed or the previous one is close to expiring;
///  * the server is told a [_timeout] so the badge clears on its own if this
///    client dies mid-word — the receiving side needs no timer of its own;
///  * a `false` is sent immediately on send, on blur and on dispose, because
///    a badge that outlives the typing is the failure people notice.
class TypingNotifier {
  TypingNotifier(this.room);

  /// How long the server should hold the badge without hearing from us again.
  ///
  /// Comfortably longer than [_resend] so an in-flight refresh cannot leave a
  /// gap, and short enough that a client which vanishes mid-sentence stops
  /// claiming to be typing within a few seconds.
  static const _timeout = Duration(seconds: 12);

  /// How often a continuing "still typing" is re-sent.
  static const _resend = Duration(seconds: 8);

  final Room room;

  bool _typing = false;
  DateTime? _sentAt;
  bool _disposed = false;

  /// Called as the composer's text changes.
  void onChanged(String text) {
    if (_disposed) return;
    if (text.trim().isEmpty) {
      unawaited(stop());
      return;
    }

    final sentAt = _sentAt;
    final stale = sentAt == null || DateTime.now().difference(sentAt) > _resend;
    if (_typing && !stale) return;

    _typing = true;
    _sentAt = DateTime.now();
    unawaited(_send(true));
  }

  /// Withdraws the notification, if one is standing.
  Future<void> stop() async {
    if (!_typing) return;
    _typing = false;
    _sentAt = null;
    await _send(false);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Deliberately not guarded by `_typing`: this is the last chance to take
    // the badge down, and sending one redundant `false` is much cheaper than
    // leaving somebody shown as typing in a room they have left.
    _typing = false;
    await _send(false);
  }

  Future<void> _send(bool typing) async {
    try {
      await room.setTyping(
        typing,
        timeout: typing ? _timeout.inMilliseconds : null,
      );
    } catch (error) {
      // Never worth surfacing. A typing notification that did not arrive costs
      // a badge somebody else did not see; failing the keystroke that caused
      // it would cost the message.
      debugPrint('[chat] typing notification failed: $error');
    }
  }
}
