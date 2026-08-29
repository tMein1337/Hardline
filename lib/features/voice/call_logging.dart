// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart';

/// The logger livekit_client writes to. Nothing listens to it by default, so
/// everything it has to say about a connection is discarded before it is born.
const _liveKitLogger = 'livekit';

StreamSubscription<LogRecord>? _subscription;

/// Pipes livekit_client's own log into the console.
///
/// Off by default and deliberately so — it is several lines per second during a
/// call — but a call that will not connect is close to undiagnosable without
/// it. The interesting half is what livekit logs at `FINE`:
///
/// ```
/// publisher onIceCandidate
/// publisher iceConnectionState: RTCIceConnectionStateChecking
/// Connected address: <host:port>
/// ```
///
/// That says how far ICE got and, on success, where the media landed. It does
/// **not** say which candidates were involved — livekit logs the arrival of a
/// candidate without logging the candidate — and `Connected address` is only
/// reached after ICE connects, so it never appears on the failure you would
/// have turned this on to diagnose. [logIceCandidates] is the half that
/// answers that.
///
/// Filtered to livekit's own logger. The Matrix SDK logs through the same
/// package and far more loudly, and burying the four lines that matter under
/// sync traffic would defeat the point.
void setVerboseCallLogging(bool enabled) {
  if (enabled == (_subscription != null)) return;

  if (!enabled) {
    unawaited(_subscription?.cancel());
    _subscription = null;
    // Back to the package default, so nothing else that starts logging later
    // inherits a level this switched on.
    Logger.root.level = Level.INFO;
    return;
  }

  Logger.root.level = Level.FINE;
  _subscription = Logger.root.onRecord.listen((record) {
    if (record.loggerName != _liveKitLogger) return;
    debugPrint('[livekit] ${record.message}');
    final error = record.error;
    if (error != null) debugPrint('[livekit]   $error');
  });
}

/// Whether the pipe is currently open. Test-only.
@visibleForTesting
bool get verboseCallLoggingActive => _subscription != null;

/// Dumps the ICE candidates and pairs a peer connection actually has.
///
/// The question a `MediaConnectException` cannot answer on its own: whether the
/// two sides ever had a route to try. Only `host` and `srflx` candidates with
/// every pair `failed` means there was no path and no relay to fall back on —
/// a NAT or firewall problem, and the case where configuring TURN is the fix.
/// `relay` candidates that still fail is a different fault entirely, and the
/// exception looks identical.
///
/// Called on a failed join, before the room is torn down, because the peer
/// connections do not survive it. Best-effort throughout: this runs while
/// something has already gone wrong, and it must not turn a failed join into a
/// crashed one.
Future<void> logIceCandidates(lk.Room? room) async {
  if (room == null) return;

  // `Room.engine` and its transports are `@internal` upstream, and there is no
  // public way to reach the peer connections. Accepted deliberately and kept to
  // this one function, the way `ScreenSelectDialog` is kept to one call site: if
  // a future livekit release moves it, one diagnostic stops compiling rather
  // than anything about the call itself changing.
  //
  // ignore: invalid_use_of_internal_member
  final transports = [
    // ignore: invalid_use_of_internal_member
    ('publisher', room.engine.publisher),
    // ignore: invalid_use_of_internal_member
    ('subscriber', room.engine.subscriber),
  ];

  for (final (label, transport) in transports) {
    if (transport == null) continue;
    try {
      // ignore: invalid_use_of_internal_member
      final reports = await transport.pc.getStats();
      var found = 0;

      for (final report in reports) {
        switch (report.type) {
          case 'local-candidate':
          case 'remote-candidate':
            found++;
            final values = report.values;
            debugPrint(
              '[livekit] $label ${report.type}: '
              '${values['candidateType']} '
              '${values['protocol']} '
              '${values['address'] ?? values['ip']}:${values['port']}',
            );
          case 'candidate-pair':
            found++;
            final values = report.values;
            debugPrint(
              '[livekit] $label pair: state=${values['state']} '
              'nominated=${values['nominated']} '
              'sent=${values['bytesSent']} received=${values['bytesReceived']}',
            );
        }
      }

      if (found == 0) {
        // No candidates at all means gathering never produced one, which is a
        // different fault again — no usable network interface, or the
        // connection was torn down before it started.
        debugPrint('[livekit] $label: no ICE candidates were gathered');
      }
    } catch (error) {
      debugPrint('[livekit] $label: could not read ICE stats: $error');
    }
  }
}
