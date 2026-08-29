// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;

/// Why a join failed, in terms somebody can act on.
///
/// Two strings because there are two places with very different room. The
/// footer is one clipped line in a narrow sidebar, so [message] has to be short
/// enough to read whole; [detail] is the sentence that says which half of the
/// stack gave up, and hangs off a tooltip.
@immutable
class JoinFailure {
  const JoinFailure(this.message, this.detail);

  /// Short enough for the call bar. A few words.
  final String message;

  /// What actually happened, and what it points at.
  final String detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoinFailure &&
          message == other.message &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(message, detail);

  @override
  String toString() => 'JoinFailure($message)';
}

/// Turns whatever `join` threw into something worth showing.
///
/// Joining a call is four systems in a row — the homeserver for an OpenID
/// token, the JWT service for an SFU token, the SFU's signalling socket, and
/// then ICE for the media itself — and every one of them can fail on its own.
/// Reporting all four as "Could not join the call" throws away the only
/// information that says which one, and turns a five-second diagnosis into a
/// bisect. This is that information, kept.
///
/// The distinction that matters most is the last two. A signalling failure
/// means the call server could not be reached at all; a media failure means it
/// *was* reached, answered, and then no audio could get through — which is a
/// firewall or NAT question and nothing to do with Matrix.
///
/// Pure over the error object, so the mapping can be tested without a call.
JoinFailure describeJoinFailure(Object error) {
  // Order matters: MediaConnectException and ConnectException are both
  // LiveKitExceptions, so the general case has to come last.
  if (error is lk.MediaConnectException) {
    return const JoinFailure(
      'No media connection',
      'The call server answered, but no audio could get through to it. That is '
          'a network path problem between this machine and the server — a '
          'firewall or a NAT — rather than anything about the call.',
    );
  }

  if (error is lk.ConnectException) {
    return const JoinFailure(
      'Call server unreachable',
      'The call server did not accept the connection. It may be down, or the '
          'address this room advertises for it may be wrong.',
    );
  }

  if (error is lk.TimeoutException) {
    return const JoinFailure(
      'Call server timed out',
      'The call server accepted the connection and then stopped answering.',
    );
  }

  if (error is lk.LiveKitException) {
    return JoinFailure(
      'Call server refused',
      'The call server rejected the connection: ${error.runtimeType}.',
    );
  }

  // The homeserver or the JWT service, before LiveKit is reached at all. Both
  // arrive as ordinary HTTP failures because both are plain requests.
  if (error is SocketException || error is http.ClientException) {
    return const JoinFailure(
      'Server unreachable',
      'Could not reach the homeserver or the call-token service. The call '
          'itself was never contacted.',
    );
  }

  return JoinFailure(
    'Could not join the call',
    'Unexpected failure: ${error.runtimeType}. The log has the whole of it.',
  );
}
