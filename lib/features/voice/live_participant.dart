// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// One video surface published by somebody in the call.
///
/// A person can have several: a camera and a screen, or two screens. Each is
/// its own feed and each gets its own tile, which is what makes somebody
/// sharing three things occupy the space of three people.
@immutable
class CallVideoFeed {
  const CallVideoFeed({
    required this.key,
    required this.track,
    required this.isScreenShare,
    required this.isLocal,
  });

  /// `identity|sid`. Stable across rebuilds, so Flutter keeps the render
  /// surface alive instead of tearing down and recreating the texture every
  /// time the controller notifies.
  final String key;

  /// **Deliberately not part of [==].**
  ///
  /// LiveKit mutates its track objects in place, so comparing them would make
  /// equality meaningless — which is exactly the trap `CallVideoTile` fell
  /// into and the reason it could never ride the `ListSnapshot` discipline the
  /// rest of the app uses. A publication sid is unique for the life of the
  /// publication, so [key] identifies the feed at least as precisely as the
  /// object does, and unlike the object it can be compared.
  final lk.VideoTrack track;

  final bool isScreenShare;
  final bool isLocal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallVideoFeed &&
          key == other.key &&
          isScreenShare == other.isScreenShare &&
          isLocal == other.isLocal;

  @override
  int get hashCode => Object.hash(key, isScreenShare, isLocal);
}

/// One person in the call this client is connected to.
///
/// The counterpart to `VoiceParticipant`, and not a replacement for it. That
/// one is built from Matrix room state and therefore exists for calls we have
/// *not* joined; this one is built from LiveKit and therefore knows things
/// room state cannot carry — whether their camera is live, and whether they
/// have muted their own microphone.
///
/// "Live" is the distinction `notes.md` draws between the two halves of a
/// MatrixRTC call: room state says who *claims* to be in it, LiveKit carries the
/// media. Everybody here is connected right now. The name also avoids a
/// collision — the Matrix SDK exports a `CallParticipant` of its own, belonging
/// to the VoIP layer this app deliberately bypasses.
///
/// One per *device*, not per person: somebody in the call from a laptop and a
/// phone is two participants here, because that is what the SFU has and each
/// one publishes its own tracks. The sidebar collapses them to one row; a grid
/// of video cannot.
@immutable
class LiveParticipant {
  const LiveParticipant({
    required this.userId,
    required this.identity,
    required this.deviceId,
    required this.displayName,
    required this.avatarMxc,
    required this.isLocal,
    required this.micMuted,
    required this.feeds,
  });

  final String userId;

  /// The raw LiveKit identity, `@user:server:DEVICEID`.
  ///
  /// Kept as well as the two halves because it is what the speaking sampler
  /// and the encryption manager key on, and re-joining it from the parts is
  /// not guaranteed to reproduce it for a client that is not ours.
  final String identity;

  final String deviceId;

  /// Already through `displaySafeName`.
  final String displayName;

  /// Raw `mxc://`, joined from the Matrix room member rather than from LiveKit,
  /// which has no notion of an avatar.
  final String? avatarMxc;

  final bool isLocal;

  /// Whether they have muted their own microphone.
  ///
  /// This is the one thing a joined call knows that the sidebar cannot: mute
  /// never reaches room state, but it does reach the SFU as the microphone
  /// publication's `muted` flag. `voice_participant.dart` is right to leave it
  /// out; a tile in a call we are connected to can honestly draw it.
  final bool micMuted;

  final List<CallVideoFeed> feeds;

  bool get isScreenSharing => feeds.any((feed) => feed.isScreenShare);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveParticipant &&
          userId == other.userId &&
          identity == other.identity &&
          deviceId == other.deviceId &&
          displayName == other.displayName &&
          avatarMxc == other.avatarMxc &&
          isLocal == other.isLocal &&
          micMuted == other.micMuted &&
          listEquals(feeds, other.feeds);

  @override
  int get hashCode => Object.hash(
    userId,
    identity,
    deviceId,
    displayName,
    avatarMxc,
    isLocal,
    micMuted,
    Object.hashAll(feeds),
  );
}

/// One cell of the call grid.
///
/// Either a video feed or, when [feed] is null, the person's avatar. The
/// avatar case is the one the old `CallVideoTile` had no way to express, which
/// is why a voice-only call used to draw nothing at all.
@immutable
class CallTile {
  const CallTile({required this.person, this.feed});

  final LiveParticipant person;
  final CallVideoFeed? feed;

  bool get isVideo => feed != null;

  /// Stable across rebuilds, for the same reason [CallVideoFeed.key] is.
  String get key => feed?.key ?? 'avatar|${person.identity}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallTile && person == other.person && feed == other.feed;

  @override
  int get hashCode => Object.hash(person, feed);
}

/// Expands people into the cells that represent them.
///
/// One tile per published feed, or one avatar tile for somebody sending
/// nothing. Pure over our own value types — no `Room`, no LiveKit — so the
/// expansion rules can be tested without a live call, which is the discipline
/// `chooseFocus` and `staleRingReceiptTarget` follow for the same reason.
///
/// Shared screens sort first because they are what people are looking at,
/// cameras next, and faces last. Within a group the order given is preserved,
/// so tiles do not reshuffle when somebody unrelated toggles a camera.
List<CallTile> tilesFor(List<LiveParticipant> participants) {
  final screens = <CallTile>[];
  final cameras = <CallTile>[];
  final avatars = <CallTile>[];

  for (final person in participants) {
    if (person.feeds.isEmpty) {
      avatars.add(CallTile(person: person));
      continue;
    }
    for (final feed in person.feeds) {
      final tile = CallTile(person: person, feed: feed);
      (feed.isScreenShare ? screens : cameras).add(tile);
    }
  }

  return [...screens, ...cameras, ...avatars];
}
