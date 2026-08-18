// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
// Prefixed: only the frame-cryptor types are needed from here, and the
// unprefixed import would collide with livekit_client's own names.
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

import 'matrix_rtc_membership.dart';

/// To-device event carrying a participant's media key.
///
/// Element Call's type. Not `com.famedly.call.encryption_keys`, which is the
/// Famedly SDK's parallel scheme and which nothing else reads.
const String kCallEncryptionKeysEventType = 'io.element.call.encryption_keys';

/// Media keys are 16 random bytes, matching Element Call.
const int _keyLength = 16;

/// Key indices wrap at 256 — one byte on the wire.
const int _keyIndexModulus = 256;

/// How long to wait after publishing a new key before encrypting with it.
///
/// Without this everyone gets a burst of undecodable frames: we would start
/// encrypting with a key that is still travelling through the homeserver. Five
/// seconds is what Element Call uses.
const Duration _useKeyDelay = Duration(seconds: 5);

/// How long the membership list must hold still before it is believed.
///
/// A rejoin is a withdrawal followed immediately by a publish, so a shorter
/// window than the gap between those two would read it as someone leaving.
const Duration _membershipSettleDelay = Duration(seconds: 2);

/// Builds a key provider whose parameters match Element Call's.
///
/// Deliberately not `BaseKeyProvider.create()`: that helper does not expose
/// `keyDerivationAlgorithm` and so leaves it at the native default of PBKDF2.
/// LiveKit's web SDK imports raw key bytes as HKDF material
/// (`createKeyMaterialFromBuffer`), and Element Call sets its media keys from
/// raw bytes — so it derives with **HKDF**.
///
/// A mismatch there is invisible in every log: the key arrives, is stored
/// against the right participant at the right index, the algorithm is AES-GCM
/// on both sides — and the derived key is simply different, so nothing
/// decodes. That is worth this much explanation because there is no error
/// message anywhere that would point at it.
///
/// The remaining values follow Element Call's provider so nothing else can
/// drift apart.
Future<lk.BaseKeyProvider> createMatrixRtcKeyProvider() async {
  final options = rtc.KeyProviderOptions(
    // MatrixRTC gives every participant their own key rather than agreeing one
    // for the room.
    sharedKey: false,
    ratchetSalt: Uint8List.fromList(lk.defaultRatchetSalt.codeUnits),
    uncryptedMagicBytes: Uint8List.fromList(lk.defaultMagicBytes.codeUnits),
    // Element Call passes 10.
    ratchetWindowSize: 10,
    // Never stop trying to decrypt. A handful of failures around a key change
    // is expected; giving up on them would turn a hiccup into silence.
    failureTolerance: -1,
    // Key indices are counted modulo 256, so the ring has to be big enough that
    // index 17 does not overwrite index 1. 255 is the documented maximum —
    // Element passes 256 to the web SDK, which this native one would reject.
    keyRingSize: 255,
    keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
  );

  final provider = await rtc.frameCryptorFactory.createDefaultKeyProvider(
    options,
  );
  return lk.BaseKeyProvider(provider, options);
}

/// Distributes and consumes the media keys for an encrypted call.
///
/// LiveKit encrypts frames with a per-participant key; Matrix is only the
/// transport that gets those keys to the right devices. Each participant makes
/// up their own key, sends it to everyone else over encrypted to-device
/// messages, and feeds keys they receive into the frame cryptor.
///
/// The two halves fit together because the LiveKit identity issued by
/// `lk-jwt-service` (`@user:server:DEVICEID`) is the same string MatrixRTC
/// calls a `memberId`, so a key arriving for a member id can be handed to
/// LiveKit unchanged.
class CallEncryptionManager {
  CallEncryptionManager({
    required this.client,
    required this.keyProvider,
    required this.roomId,
    required this.localIdentity,
    required this.onOwnKeyIndexChanged,
  });

  final Client client;
  final lk.BaseKeyProvider keyProvider;
  final String roomId;

  /// Our LiveKit participant identity, taken from the connected room rather
  /// than rebuilt from `userId:deviceId`.
  ///
  /// They are the same string today, but only because of how the token service
  /// happens to mint identities. Deriving it would make the frame cryptor
  /// silently fail the day that changes, and a key stored under the wrong
  /// identity produces no error anywhere.
  final String localIdentity;

  /// Tells the live sender which key index to encrypt with.
  ///
  /// Necessary because `E2EEManager` reads the index **once**, when a track is
  /// published (`_addRtpSender`). A key rotated afterwards is stored and
  /// distributed, but the running sender keeps encrypting with the old index
  /// until something pushes the new one — so without this, everyone stops
  /// hearing us after the first rotation.
  final Future<void> Function(int keyIndex) onOwnKeyIndexChanged;

  /// What we call ourselves in the MatrixRTC membership, which is what
  /// recipients match a key against. Distinct from [localIdentity] on purpose.
  String get _membershipId => '${client.userID}:${client.deviceID}';

  final _random = Random.secure();
  StreamSubscription<ToDeviceEvent>? _subscription;

  Uint8List? _outboundKey;
  int _keyIndex = 0;
  bool _disposed = false;

  Timer? _settleTimer;
  List<MatrixRtcMembership>? _pendingMemberships;

  /// Member ids we have already sent the current key to.
  ///
  /// Tracked so a participant joining mid-call gets the key without everyone
  /// re-sending theirs on every membership heartbeat.
  final Set<String> _sentTo = {};


  /// Starts listening for other people's keys and publishes our first one.
  Future<void> start(List<MatrixRtcMembership> memberships) async {
    _subscription = client.onToDeviceEvent.stream.listen(_onToDeviceEvent);
    await _rotateKey(memberships);
  }

  /// Reacts to the call's membership list changing.
  ///
  /// Coalesced, because membership state arrives in bursts: joining publishes
  /// our own event, participants republish as an expiry heartbeat, and a rejoin
  /// is a withdrawal immediately followed by a publish. Acting on each event
  /// individually sees people "leave" in the gaps and rotates the key for
  /// nothing — and every rotation costs the whole call [_useKeyDelay] of
  /// silence, so a spurious one is not a harmless extra round trip.
  void onMembershipsChanged(List<MatrixRtcMembership> memberships) {
    if (_disposed) return;
    _pendingMemberships = memberships;
    _settleTimer?.cancel();
    _settleTimer = Timer(_membershipSettleDelay, () {
      final pending = _pendingMemberships;
      if (_disposed || pending == null) return;
      _pendingMemberships = null;
      unawaited(_applyMembershipChange(pending));
    });
  }

  Future<void> _applyMembershipChange(
    List<MatrixRtcMembership> memberships,
  ) async {
    if (_disposed) return;

    final current = memberships
        .map((m) => '${m.userId}:${m.deviceId}')
        .where((id) => id != _membershipId)
        .toSet();

    final departed = _sentTo.difference(current);
    if (departed.isNotEmpty) {
      debugPrint('[voice] rotating media key, ${departed.length} left');
      await _rotateKey(memberships);
      return;
    }

    final arrived = current.difference(_sentTo);
    if (arrived.isNotEmpty) {
      await _sendKeyTo(memberships, only: arrived);
    }
  }

  /// Makes a new key, publishes it, then starts using it.
  Future<void> _rotateKey(List<MatrixRtcMembership> memberships) async {
    final key = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => _random.nextInt(256)),
    );
    _outboundKey = key;
    _keyIndex = (_keyIndex + 1) % _keyIndexModulus;
    _sentTo.clear();

    await _sendKeyTo(memberships);

    // Publish before adopting: encrypting with a key nobody has yet would just
    // produce noise for everyone until it arrived.
    await Future<void>.delayed(_useKeyDelay);
    if (_disposed) return;

    await keyProvider.setRawKey(
      key,
      participantId: localIdentity,
      keyIndex: _keyIndex,
    );

    // Storing the key is not enough: the running sender captured its key index
    // when the track was published and will keep using it otherwise.
    await onOwnKeyIndexChanged(_keyIndex);

    debugPrint(
      '[voice] using own media key index $_keyIndex as $localIdentity',
    );
  }

  /// Sends the current key to [only], or to every other participant.
  Future<void> _sendKeyTo(
    List<MatrixRtcMembership> memberships, {
    Set<String>? only,
  }) async {
    final key = _outboundKey;
    if (key == null) return;

    // Encrypted to-device requires knowing the recipients' devices. Anyone
    // whose keys we do not have is skipped rather than sent to in the clear —
    // a media key in plaintext would defeat the entire exercise.
    final targets = <DeviceKeys>[];
    for (final membership in memberships) {
      final memberId = '${membership.userId}:${membership.deviceId}';
      if (memberId == _membershipId) continue;
      if (only != null && !only.contains(memberId)) continue;

      final device =
          client.userDeviceKeys[membership.userId]?.deviceKeys[membership
              .deviceId];
      if (device == null) {
        debugPrint('[voice] no device keys for $memberId, skipping key send');
        continue;
      }
      targets.add(device);
      _sentTo.add(memberId);
    }

    if (targets.isEmpty) return;

    final content = {
      'keys': {'index': _keyIndex, 'key': base64Encode(key)},
      'room_id': roomId,
      'member': {
        'id': _membershipId,
        'claimed_device_id': client.deviceID,
      },
      'session': {
        'call_id': '',
        'application': kCallApplication,
        'scope': 'm.room',
      },
      'sent_ts': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      await client.sendToDeviceEncrypted(
        targets,
        kCallEncryptionKeysEventType,
        content,
      );
      debugPrint(
        '[voice] sent media key $_keyIndex to ${targets.length} device(s)',
      );
    } catch (error, stack) {
      debugPrint('[voice] sending media key failed: $error\n$stack');
    }
  }

  /// Works out which LiveKit participant a received key decrypts.
  ///
  /// **Not** from `member.id`. That is a `membershipID`, and current Element
  /// sets it to a random UUID — only clients old enough to omit it fall back to
  /// the `userId:deviceId` form, so reading it as an identity works against
  /// exactly the clients that no longer exist.
  ///
  /// The identity is rebuilt from the *authenticated* sender plus the claimed
  /// device instead. The user half therefore cannot be forged: an attacker can
  /// only ever name their own devices, which they are entitled to publish from
  /// anyway. Contrast with trusting `member.id`, where any room member could
  /// submit a key attributed to someone else and have that person's stream
  /// decoded as theirs.
  String? _participantIdFor(ToDeviceEvent event, Map<Object?, Object?> member) {
    final claimedDeviceId = member['claimed_device_id'];
    if (claimedDeviceId is String && claimedDeviceId.isNotEmpty) {
      return '${event.sender}:$claimedDeviceId';
    }

    // No claimed device: fall back to matching the membership id against room
    // state, which still yields a device — restricted to memberships published
    // by the sender, so the same forgery argument holds.
    final membershipId = member['id'];
    if (membershipId is! String || membershipId.isEmpty) return null;

    final room = client.getRoomById(roomId);
    if (room == null) return null;
    for (final membership in liveMembershipsOf(room)) {
      if (membership.userId != event.sender) continue;
      if (membership.membershipId != membershipId) continue;
      return '${membership.userId}:${membership.deviceId}';
    }
    return null;
  }

  void _onToDeviceEvent(ToDeviceEvent event) {
    if (_disposed) return;
    if (event.type != kCallEncryptionKeysEventType) return;

    try {
      final content = event.content;
      if (content['room_id'] != roomId) return;

      final keys = content['keys'];
      if (keys is! Map) return;
      final index = keys['index'];
      final encoded = keys['key'];
      if (index is! int || encoded is! String) return;

      final member = content['member'];
      if (member is! Map) return;

      final participantId = _participantIdFor(event, member);
      if (participantId == null) {
        debugPrint(
          '[voice] discarding media key from ${event.sender}: '
          'cannot resolve which participant it belongs to',
        );
        return;
      }

      final key = base64Decode(encoded);
      unawaited(
        keyProvider
            .setRawKey(key, participantId: participantId, keyIndex: index)
            .then(
              (_) => debugPrint('[voice] media key $index from $participantId'),
            ),
      );
    } catch (error, stack) {
      debugPrint('[voice] unreadable media key: $error\n$stack');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _settleTimer?.cancel();
    _settleTimer = null;
    _pendingMemberships = null;
    await _subscription?.cancel();
    _subscription = null;
    _outboundKey = null;
    _sentTo.clear();
  }
}
