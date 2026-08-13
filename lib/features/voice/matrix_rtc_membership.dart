import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// The MatrixRTC call membership state event type, as Element Call writes it.
///
/// Deliberately a literal rather than `EventTypes.GroupCallMember`. That SDK
/// constant is `com.famedly.call.member` — a Famedly-proprietary parallel
/// implementation which no Element client reads or writes. Using it here would
/// produce calls that only this app can see.
const String kCallMemberEventType = 'org.matrix.msc3401.call.member';

/// The MatrixRTC "slot"/application id for ordinary voice+video calls.
const String kCallApplication = 'm.call';

/// The timeline events a client sends to make everyone else's phone ring.
///
/// Three spellings because the MSC was renamed twice and clients in the wild
/// still send all of them. This is **not** the membership: a ring is an
/// ordinary timeline event that says "a call is starting, now", and it is what
/// actually produces the unread badge — Element sends it carrying
/// `m.mentions: {room: true}`, so the homeserver's `@room` push rule gives it a
/// highlight tweak and counts it against the room.
///
/// Nothing here renders them, which is why a call can leave a room showing a
/// red 1 with an apparently empty timeline.
const Set<String> kRtcRingEventTypes = {
  'org.matrix.msc4075.rtc.notification',
  'org.matrix.msc4075.call.notify',
  'm.call.notify',
};

/// How long a ring is meant to stand, absent an explicit `lifetime`.
///
/// MSC4075 has the sender state it; Element sends 30 s. A ring is a *doorbell*,
/// not a message — past its lifetime it is describing an event that has already
/// happened, and there is nothing left to answer.
const Duration kDefaultRingLifetime = Duration(seconds: 30);

/// Whether a ring has stopped meaning anything.
///
/// True once its own lifetime has run out. Note this deliberately takes the
/// content rather than an `Event`: the ring usually has to be judged from a
/// `/notifications` response, where there is no `Room` to hang an `Event` on.
///
/// `sender_ts` is preferred over the event's `origin_server_ts` because it is
/// what MSC4075 defines the lifetime against, but it is optional, so the
/// caller's timestamp is the fallback.
bool isRingExpired(
  Map<String, Object?> content, {
  required DateTime originServerTs,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();

  final senderTs = content['sender_ts'];
  final sent = senderTs is int
      ? DateTime.fromMillisecondsSinceEpoch(senderTs)
      : originServerTs;

  final lifetimeMs = content['lifetime'];
  final lifetime = lifetimeMs is int && lifetimeMs > 0
      ? Duration(milliseconds: lifetimeMs)
      : kDefaultRingLifetime;

  return reference.isAfter(sent.add(lifetime));
}

/// How long a published membership stays valid, absent an explicit `expires`.
const Duration kDefaultMembershipLifetime = Duration(hours: 4);

/// How long after our last heartbeat the server withdraws our membership.
///
/// This is the MSC4140 delay: the withdrawal is scheduled on the homeserver at
/// join time and pushed back every [kDelayedLeaveHeartbeat] while we are alive,
/// so a process that dies without running any code — a Task Manager kill, a
/// power cut — still disappears from the channel about this long afterwards
/// instead of lingering until `expires`.
///
/// Long enough to survive a stalled request or a brief network blip, short
/// enough that nobody is left staring at a participant who is not there. The
/// SDK's own VoIP layer uses 18 s for the same purpose.
const Duration kDelayedLeaveAfter = Duration(seconds: 20);

/// How often the pending withdrawal is pushed back.
///
/// Four heartbeats per delay window, so three can be lost in a row before the
/// server acts. These are POSTs to the delayed-events endpoint, not room
/// events, so unlike the membership itself they cost the timeline nothing.
const Duration kDelayedLeaveHeartbeat = Duration(seconds: 5);

/// Where a call's media is relayed.
///
/// Only LiveKit is modelled: it is what this homeserver deploys and what
/// Element Call uses. An unknown focus type parses to null rather than
/// throwing, so a future backend cannot break the participant list.
@immutable
class LiveKitFocus {
  const LiveKitFocus({required this.serviceUrl, required this.alias});

  /// Base URL of an `lk-jwt-service` deployment.
  final String serviceUrl;

  /// The LiveKit room name, which Element sets to the Matrix room id.
  final String alias;

  static LiveKitFocus? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['type'] != 'livekit') return null;
    final url = json['livekit_service_url'];
    final alias = json['livekit_alias'];
    if (url is! String || url.isEmpty) return null;
    return LiveKitFocus(
      serviceUrl: url,
      alias: alias is String ? alias : '',
    );
  }

  Map<String, Object?> toJson() => {
    'type': 'livekit',
    'livekit_service_url': serviceUrl,
    'livekit_alias': alias,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveKitFocus &&
          serviceUrl == other.serviceUrl &&
          alias == other.alias;

  @override
  int get hashCode => Object.hash(serviceUrl, alias);
}

/// One device's presence in a room's call.
///
/// This is the MSC4143 shape: **one membership per state event**, keyed by
/// `_{userId}_{deviceId}_{slotId}`. It is not the older Famedly/MSC3401 shape
/// where a single event held a `memberships: []` array — do not reintroduce
/// that, the two are not interchangeable.
///
/// Every field is parsed defensively. These events come from other people's
/// clients across several implementations and versions, and one malformed
/// event must never take down the room list.
@immutable
class MatrixRtcMembership {
  const MatrixRtcMembership({
    required this.userId,
    required this.deviceId,
    required this.membershipId,
    required this.application,
    required this.createdTs,
    required this.expires,
    required this.focusPreferred,
    required this.intent,
  });

  final String userId;
  final String deviceId;

  /// The `membershipID` this participant published.
  ///
  /// Opaque. Older clients default it to `userId:deviceId`, current Element
  /// uses a random UUID — so it identifies a membership but says nothing about
  /// who or which device, and must never be parsed for either.
  final String membershipId;

  /// `m.call` for ordinary calls. Other values are other kinds of session.
  final String application;

  final DateTime createdTs;
  final Duration expires;

  /// The SFUs this participant offered. Joining the same call means reusing one
  /// of these rather than picking our own, or we would end up on a different
  /// server and hear nobody.
  final List<LiveKitFocus> focusPreferred;

  /// `audio` or `video`, per `m.call.intent`. Advisory only.
  final String? intent;

  DateTime get expiresAt => createdTs.add(expires);

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isCall => application == kCallApplication;

  /// Parses a membership from a state event's content.
  ///
  /// Returns null when the content is empty — **that is how leaving is
  /// represented**. Element clears the content to `{}` rather than redacting
  /// the event, so "has a state event" does not mean "is in the call"; every
  /// membership in a freshly synced room is typically an empty tombstone from
  /// someone who left hours ago.
  static MatrixRtcMembership? fromContent({
    required Map<String, Object?> content,
    required String userId,
  }) {
    if (content.isEmpty) return null;

    final deviceId = content['device_id'];
    if (deviceId is! String || deviceId.isEmpty) return null;

    final application = content['application'];

    final createdRaw = content['created_ts'];
    final createdTs = createdRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(createdRaw)
        // Some clients omit created_ts on the first publish and rely on the
        // event's origin_server_ts. Treating it as "now" keeps the membership
        // live rather than instantly expiring it.
        : DateTime.now();

    final expiresRaw = content['expires'];
    final expires = expiresRaw is int && expiresRaw > 0
        ? Duration(milliseconds: expiresRaw)
        : kDefaultMembershipLifetime;

    final fociRaw = content['foci_preferred'];
    final foci = <LiveKitFocus>[];
    if (fociRaw is List) {
      for (final entry in fociRaw) {
        final focus = LiveKitFocus.fromJson(entry);
        if (focus != null) foci.add(focus);
      }
    }

    final intent = content['m.call.intent'];
    final membershipId = content['membershipID'];

    return MatrixRtcMembership(
      userId: userId,
      deviceId: deviceId,
      membershipId: membershipId is String ? membershipId : '',
      application: application is String ? application : kCallApplication,
      createdTs: createdTs,
      expires: expires,
      focusPreferred: foci,
      intent: intent is String ? intent : null,
    );
  }

  /// The state key this membership must be published under.
  ///
  /// The leading underscore marks an MSC3757 "unprotected" per-device key,
  /// which is what lets one user hold several memberships (one per device)
  /// without them overwriting each other.
  static String stateKeyFor({
    required String userId,
    required String deviceId,
    String application = kCallApplication,
  }) => '_${userId}_${deviceId}_$application';

  /// Extracts the user id from a state key, or null if it does not parse.
  ///
  /// Preferred over trusting the event's `sender`, since the state key is what
  /// the server validates against the sender for `_`-prefixed keys.
  static String? userIdFromStateKey(String stateKey) {
    if (!stateKey.startsWith('_@')) return null;
    // `_@user:server_DEVICEID_m.call` — the user id ends at the first `_`
    // after the server name, and neither user ids nor server names may contain
    // `_`... but device ids and the application may, so scan from the left.
    final rest = stateKey.substring(1);
    final firstUnderscore = rest.indexOf('_');
    if (firstUnderscore <= 0) return null;
    final userId = rest.substring(0, firstUnderscore);
    return userId.contains(':') ? userId : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatrixRtcMembership &&
          userId == other.userId &&
          deviceId == other.deviceId &&
          application == other.application &&
          createdTs == other.createdTs &&
          expires == other.expires &&
          intent == other.intent &&
          listEquals(focusPreferred, other.focusPreferred);

  @override
  int get hashCode => Object.hash(
    userId,
    deviceId,
    application,
    createdTs,
    expires,
    intent,
    Object.hashAll(focusPreferred),
  );
}

/// Every live call membership in [room].
///
/// Reads `org.matrix.msc3401.call.member` state directly. Needs no permission
/// and no decryption — state events are never encrypted, which is exactly what
/// makes "see who is in a call without joining" possible.
///
/// Most membership events in a synced room are empty tombstones from people who
/// left, so this filters rather than maps: a room with twenty state events may
/// well have nobody in the call.
List<MatrixRtcMembership> liveMembershipsOf(Room room) {
  final states = room.states[kCallMemberEventType];
  if (states == null || states.isEmpty) return const [];

  final result = <MatrixRtcMembership>[];
  for (final entry in states.entries) {
    // The state key is authoritative over `sender`: for `_`-prefixed keys the
    // server enforces that they match, and the key is what identifies the
    // device this membership belongs to.
    final userId =
        MatrixRtcMembership.userIdFromStateKey(entry.key) ??
        entry.value.senderId;

    final membership = MatrixRtcMembership.fromContent(
      content: entry.value.content,
      userId: userId,
    );
    if (membership == null) continue;
    if (!membership.isCall || membership.isExpired) continue;
    result.add(membership);
  }
  return result;
}
