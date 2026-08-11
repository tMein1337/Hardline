import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';

/// One of the user's own sessions, as the settings list needs it.
///
/// Two sources have to be merged for a complete row and neither is enough
/// alone: `/devices` knows the name and when it was last seen, the device keys
/// know whether it is verified. A session can appear in one and not the other —
/// a brand new session has no keys uploaded yet, and a session signed out
/// elsewhere can linger in the local key store.
@immutable
class SessionInfo {
  const SessionInfo({
    required this.deviceId,
    required this.isCurrent,
    required this.verified,
    required this.canVerify,
    this.displayName,
    this.lastSeenIp,
    this.lastSeenAt,
  });

  final String deviceId;
  final bool isCurrent;
  final bool verified;

  /// False when the homeserver has no keys for this session, which is what
  /// happens before it has ever run an encryption-capable client. Starting a
  /// verification against it would fail immediately.
  final bool canVerify;

  final String? displayName;
  final String? lastSeenIp;
  final DateTime? lastSeenAt;

  String get label => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : 'Unnamed session';
}

/// The raw `/devices` response.
///
/// Its own provider so it can be refreshed on demand — it is a network call,
/// and the sessions list must not re-fetch it on every sync tick.
final deviceListProvider = FutureProvider<List<Device>>((ref) async {
  final client = ref.watch(clientProvider);
  return await client.getDevices() ?? const [];
});

/// The merged list: current session first, then the rest by last seen.
///
/// Watches the sync tick so a verification completing updates the badge without
/// anyone having to reload the pane — verification state arrives over to-device
/// messages, not through `/devices`.
///
/// **Synchronous on purpose.** This used to be a `FutureProvider` that awaited
/// `deviceListProvider.future`, which made the sync tick a *dependency of an
/// async rebuild*: every sync burst — one every few hundred milliseconds —
/// threw it back to `AsyncLoading`, and `when(loading:)` replaced the whole
/// pane with a spinner. It looked fine on first open and blank ever after,
/// because by the time you came back the tick had moved and it never settled.
///
/// Reading the device list as an `AsyncValue` instead means a tick recomputes
/// the verification badges from the key store instantly, and only a genuine
/// re-fetch of `/devices` can show a loading state.
final sessionsProvider = Provider<AsyncValue<List<SessionInfo>>>((ref) {
  final client = ref.watch(clientProvider);
  ref.watch(matrixTickProvider);

  return ref.watch(deviceListProvider).whenData((devices) {
    final keys = client.userDeviceKeys[client.userID]?.deviceKeys ?? const {};
    final currentDeviceId = client.deviceID;

    final sessions = [
      for (final device in devices)
        SessionInfo(
          deviceId: device.deviceId,
          isCurrent: device.deviceId == currentDeviceId,
          // The current session is trivially trustworthy: it is the one asking.
          // The SDK does not mark it verified until cross-signing is set up,
          // and warning about the device the user is sitting at is noise.
          verified:
              device.deviceId == currentDeviceId ||
              (keys[device.deviceId]?.verified ?? false),
          canVerify:
              device.deviceId != currentDeviceId &&
              keys.containsKey(device.deviceId),
          displayName: device.displayName,
          lastSeenIp: device.lastSeenIp,
          lastSeenAt: device.lastSeenTs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(device.lastSeenTs!),
        ),
    ];

    sessions.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      final aSeen = a.lastSeenAt;
      final bSeen = b.lastSeenAt;
      if (aSeen == null || bSeen == null) {
        return aSeen == bSeen ? 0 : (aSeen == null ? 1 : -1);
      }
      return bSeen.compareTo(aSeen);
    });

    return sessions;
  });
});
