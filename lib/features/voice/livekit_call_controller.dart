import 'dart:async';

import 'package:flutter/foundation.dart';
// Prefixed: flutter_webrtc exports a `MediaDevices` that collides with
// webrtc_interface's, and we only need `Helper` from it here.
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

import 'audio_devices_provider.dart';
import 'call_encryption_manager.dart';
import 'delayed_leave.dart';
import 'livekit_token_service.dart';
import 'matrix_rtc_membership.dart';
import 'voice_joinability.dart';
import 'voice_prefs_state.dart';

enum CallStatus { idle, joining, connected, leaving, failed }

/// One video surface on the call stage.
///
/// A plain value so the UI can rebuild from a list without reaching into
/// LiveKit's mutable participant objects — the same discipline the room list
/// follows, for the same reason.
@immutable
class CallVideoTile {
  const CallVideoTile({
    required this.key,
    required this.userId,
    required this.displayName,
    required this.track,
    required this.isScreenShare,
    required this.isLocal,
  });

  /// Stable across rebuilds so Flutter keeps the render surface alive instead
  /// of tearing down and recreating the texture on every notify.
  final String key;

  final String userId;
  final String displayName;
  final lk.VideoTrack track;
  final bool isScreenShare;
  final bool isLocal;
}

/// Recovers the Matrix user id from a LiveKit participant identity.
///
/// `lk-jwt-service`'s legacy endpoint builds the identity as
/// `matrixUserId + ":" + deviceId`, e.g. `@bob:example.org:ABCDEFGH`. Splitting
/// on the *last* colon is essential — a Matrix id contains one itself, so
/// splitting on the first would yield `@bob`.
///
/// Falls back to the raw identity when it does not look like one of ours,
/// which keeps a participant from a different client from vanishing entirely.
String matrixUserIdOf(String identity) {
  final lastColon = identity.lastIndexOf(':');
  if (lastColon <= 0) return identity;
  final candidate = identity.substring(0, lastColon);
  return candidate.startsWith('@') && candidate.contains(':')
      ? candidate
      : identity;
}

/// Recovers the Matrix device id from a LiveKit participant identity.
///
/// The counterpart to [matrixUserIdOf] — everything after the last colon.
/// Returns an empty string when the identity is not one of ours, which the
/// preferences treat as "unknown device" and therefore leave at default gain.
String matrixDeviceIdOf(String identity) {
  final lastColon = identity.lastIndexOf(':');
  if (lastColon <= 0) return '';
  final userId = identity.substring(0, lastColon);
  if (!userId.startsWith('@') || !userId.contains(':')) return '';
  return identity.substring(lastColon + 1);
}

/// How long before a published membership expires that we republish it.
///
/// Memberships carry `expires` (4h by default). Republishing well before the
/// deadline means a missed refresh — a suspended laptop, a flaky network — has
/// a second chance before other clients drop us from their participant lists.
const _membershipRefreshLead = Duration(minutes: 30);

/// Owns the one call this client is in.
///
/// A `ChangeNotifier` for the same reason `TimelineController` is one: call
/// state is mutable and high-frequency, and value-equality snapshots would be
/// all cost and no benefit.
///
/// **It deliberately breaks the codebase's usual reactivity rule.** Everything
/// else derives from `matrixTickProvider`, which debounces 120ms with a 500ms
/// max wait — right for a room list, wrong for a mute button. This listens to
/// LiveKit's own event stream instead and never touches the tick.
///
/// Unlike `timelineControllerProvider` it is app-scoped and never auto-disposed,
/// because a call has to survive switching rooms and spaces.
///
/// ## Two halves that must stay in sync
///
/// A MatrixRTC call is two independent systems:
///
///  * **Matrix room state** (`org.matrix.msc3401.call.member`) says who *claims*
///    to be in the call. This is what non-participants see.
///  * **LiveKit** carries the actual media.
///
/// Nothing enforces agreement between them. If we connect to LiveKit but fail
/// to publish state, we are audible to people already in the call but invisible
/// to everyone else. If we publish state but fail to connect, we appear in the
/// channel as a participant nobody can hear. Order matters, and both directions
/// are handled explicitly below.
class LiveKitCallController extends ChangeNotifier {
  LiveKitCallController({
    required this.client,
    required this.tokenService,
    required this.readPrefs,
  }) {
    assert(() {
      liveInstanceCount++;
      return true;
    }());
  }

  final Client client;
  final LiveKitTokenService tokenService;

  /// Reads the current settings on demand.
  ///
  /// A callback rather than a stored value so the controller always sees the
  /// latest preferences without having to be rebuilt — and so it stays free of
  /// Riverpod, which keeps it testable.
  final VoicePrefsState Function() readPrefs;

  /// Persist hooks, wired by the provider.
  ///
  /// Callbacks rather than a direct dependency on the prefs notifier for the
  /// same reason as [readPrefs]: this class stays testable without Riverpod.
  void Function(bool muted)? onSelfMuteChanged;
  void Function(bool deafened)? onDeafenChanged;

  /// Debug-only leak counter. Should never exceed 1.
  @visibleForTesting
  static int liveInstanceCount = 0;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  Timer? _refreshTimer;
  bool _disposed = false;

  /// Null when no call is up, or when the homeserver has no MSC4140 support.
  DelayedLeave? _delayedLeave;

  /// Null in unencrypted rooms, where there are no media keys to exchange.
  CallEncryptionManager? _encryption;
  StreamSubscription<({String roomId, StrippedStateEvent state})>?
  _membershipSubscription;

  CallStatus _status = CallStatus.idle;
  String? _roomId;
  String? _error;
  bool _micMuted = false;
  bool _deafened = false;

  /// What the microphone was doing before deafening, so undeafening restores
  /// it rather than unconditionally switching it on.
  bool _micMutedBeforeDeafen = false;

  /// Coalescing guard for [_reapplyAudioState]; see its doc comment.
  bool _reapplyInFlight = false;
  bool _reapplyDirty = false;

  CallStatus get status => _status;
  String? get roomId => _roomId;
  String? get error => _error;
  bool get micMuted => _micMuted;
  bool get deafened => _deafened;
  bool get isInCall => _status == CallStatus.connected;

  bool isInCallFor(String roomId) => isInCall && _roomId == roomId;

  /// The live LiveKit room, for UI that renders participants and tracks.
  lk.Room? get liveKitRoom => _room;

  /// Joins the call in [matrixRoomId], switching rooms if already in another.
  ///
  /// Switching is a leave followed by a join rather than two overlapping
  /// connections: the SFU token is scoped to one room, and staying in the old
  /// call would leave a membership advertised in a channel we are no longer
  /// listening to — other people would keep seeing us there and wonder why we
  /// never answer.
  Future<void> join(String matrixRoomId) async {
    // A join or leave already in flight owns the state machine; a second one
    // racing it would interleave connect and disconnect unpredictably.
    if (_status == CallStatus.joining || _status == CallStatus.leaving) return;

    // Already here — nothing to do, and tearing down to rebuild the same call
    // would just drop the audio for a moment.
    if (isInCall && _roomId == matrixRoomId) return;

    // Keyed on the LiveKit room rather than on `isInCall`, so a connection left
    // over from a failed join is torn down too. Overwriting `_room` without
    // disconnecting would leak the old connection and keep its membership
    // published.
    if (_room != null) await leave();

    final room = client.getRoomById(matrixRoomId);
    if (room == null) return;

    _status = CallStatus.joining;
    _roomId = matrixRoomId;
    _error = null;
    notifyListeners();

    try {
      await room.postLoad();

      if (joinabilityOf(room) == VoiceJoinability.forbidden ||
          joinabilityOf(room) == VoiceJoinability.notJoined) {
        throw _VoiceUserError(
          'You do not have permission to join calls in this room.',
        );
      }

      // Reuse the SFU everyone else is already on. Picking our own focus would
      // put us in a different LiveKit room with the same name on a different
      // server — we would connect successfully and hear nobody, which is far
      // harder to diagnose than a clean failure.
      final focus = _resolveFocus(room);
      if (focus == null) {
        throw _VoiceUserError(
          'No call server is configured for this room.',
        );
      }

      final credentials = await tokenService.fetch(
        serviceUrl: focus.serviceUrl,
        roomId: matrixRoomId,
      );

      // Media encryption mirrors the Matrix room: an encrypted room gets
      // encrypted frames, an unencrypted one does not. Turning it on
      // unilaterally would make us undecodable to everyone else in the call,
      // since they follow the same rule.
      //
      // Parameters have to match Element Call's exactly — see
      // `createMatrixRtcKeyProvider` for why the defaults do not.
      lk.BaseKeyProvider? keyProvider;
      if (room.encrypted) {
        keyProvider = await createMatrixRtcKeyProvider();
      }

      final lkRoom = lk.Room(
        roomOptions: lk.RoomOptions(
          encryption: keyProvider == null
              ? null
              : lk.E2EEOptions(keyProvider: keyProvider),
        ),
      );
      _listener = lkRoom.createListener();
      _attachListeners();

      await lkRoom.connect(credentials.url, credentials.token);
      _room = lkRoom;

      if (keyProvider != null) {
        // Started before publishing anything: our first frames must already be
        // encrypted with a key the others have.
        final encryption = CallEncryptionManager(
          client: client,
          keyProvider: keyProvider,
          roomId: matrixRoomId,
          // The identity LiveKit actually assigned us, not one rebuilt from
          // the Matrix ids — a key filed under the wrong identity fails
          // silently.
          localIdentity: lkRoom.localParticipant?.identity ?? '',
          onOwnKeyIndexChanged: (index) async =>
              lkRoom.e2eeManager?.setKeyIndex(index),
        );
        _encryption = encryption;
        await encryption.start(liveMembershipsOf(room));

        // Key rotation is driven by Matrix room state, not by LiveKit: someone
        // is "gone" when they withdraw their membership, which can happen
        // before or after their SFU connection drops.
        _membershipSubscription = client.onRoomState.stream
            .where((update) => update.roomId == matrixRoomId)
            .where((update) => update.state.type == kCallMemberEventType)
            .listen((_) {
              final current = client.getRoomById(matrixRoomId);
              if (current == null) return;
              // Returns immediately; the manager coalesces the burst itself.
              encryption.onMembershipsChanged(liveMembershipsOf(current));
            });
      }

      // Before publishing, not after: the track captures from whichever device
      // is selected at the moment it is created, so selecting afterwards would
      // require restarting it and the first seconds would come from the wrong
      // microphone.
      await applyAudioDevices();

      // Microphone only. Camera and screenshare are opt-in later; grabbing the
      // camera to join a voice channel would light the hardware indicator for
      // no reason.
      final publication = await lkRoom.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: await _micCaptureOptions(),
      );
      if (publication == null) {
        // Not fatal — we may still want to listen — but it means nobody can
        // hear us, and silence is otherwise indistinguishable from everyone
        // being quiet.
        debugPrint('[voice] WARNING: microphone did not publish');
      }

      await logAudioDevices();
      logDiagnostics('after connect');

      // Media is up, so publish state last: a participant others can hear but
      // cannot see is a better failure than the reverse.
      await _publishMembership(room, focus);
      _scheduleMembershipRefresh(room, focus);
      await _armDelayedLeave(room, focus);

      if (_disposed) {
        await leave();
        return;
      }

      _status = CallStatus.connected;
      _micMuted = false;

      // Restore how the user left things last time. `persist: false` because
      // these values came *from* storage — writing them back would be a no-op
      // at best and could clobber a concurrent change at worst.
      final prefs = readPrefs();
      _deafened = prefs.deafened;
      _micMutedBeforeDeafen = prefs.selfMuted;
      if (prefs.selfMuted || prefs.deafened) {
        await setMicMuted(true, persist: false);
      }
      await _reapplyAudioState();

      notifyListeners();
    } catch (error, stack) {
      debugPrint('[voice] joining $matrixRoomId failed: $error\n$stack');
      await _teardown(matrixRoomId);
      _status = CallStatus.failed;
      _error = error is _VoiceUserError
          ? error.message
          : 'Could not join the call.';
      notifyListeners();
    }
  }

  Future<void> leave() async {
    if (_room == null && _status == CallStatus.idle) return;

    final matrixRoomId = _roomId;
    _status = CallStatus.leaving;
    notifyListeners();

    await _teardown(matrixRoomId);

    _status = CallStatus.idle;
    _roomId = null;
    _micMuted = false;
    _cameraOn = false;
    _screenSharing = false;
    if (!_disposed) notifyListeners();
  }

  /// Clears our membership and disconnects, in that order.
  ///
  /// State first: it is the half other people's clients render, so withdrawing
  /// it promptly is what makes us disappear from their channel list. A failure
  /// here must not prevent the disconnect, or we would keep sending audio while
  /// appearing to have left.
  Future<void> _teardown(String? matrixRoomId) async {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    // Before the membership is cleared, not after. A withdrawal left scheduled
    // fires against whatever the state looks like ~20 s from now, and if the
    // user rejoins in the meantime that is a membership they want to keep.
    final delayedLeave = _delayedLeave;
    _delayedLeave = null;
    if (delayedLeave != null) {
      try {
        await delayedLeave.disarm();
      } catch (error, stack) {
        debugPrint('[voice] disarming the delayed leave failed: $error\n$stack');
      }
    }

    if (matrixRoomId != null) {
      try {
        await _clearMembership(matrixRoomId);
      } catch (error, stack) {
        debugPrint('[voice] clearing membership failed: $error\n$stack');
      }
    }

    await _membershipSubscription?.cancel();
    _membershipSubscription = null;

    // Before the disconnect, so no key is generated for a call we are leaving.
    await _encryption?.dispose();
    _encryption = null;

    try {
      await _listener?.dispose();
    } catch (_) {}
    _listener = null;

    try {
      await _room?.disconnect();
      await _room?.dispose();
    } catch (error, stack) {
      debugPrint('[voice] disconnect failed: $error\n$stack');
    }
    _room = null;
  }

  Future<void> setMicMuted(bool muted, {bool persist = true}) async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    try {
      // No `audioCaptureOptions` on the unmute: livekit reads them only for
      // `stopAudioCaptureOnMute` once a publication exists, and restarts the
      // track from the options it already holds. Passing them here looked like
      // it pinned the device and did nothing. `applyAudioDevices` is what
      // keeps those options current, including while muted.
      await participant.setMicrophoneEnabled(!muted);
      _micMuted = muted;
      if (persist) onSelfMuteChanged?.call(muted);
      notifyListeners();
    } catch (error, stack) {
      debugPrint('[voice] mute toggle failed: $error\n$stack');
    }
  }

  /// Silences everyone else, locally.
  ///
  /// Nothing about this goes on the wire — deafening is a property of *our*
  /// playback, not of the call. It also mutes our own microphone, the way
  /// Discord does, on the reasoning that someone who cannot hear the room
  /// should not be talking into it.
  Future<void> setDeafened(bool deafened) async {
    if (deafened) {
      _micMutedBeforeDeafen = _micMuted;
      _deafened = true;
      await setMicMuted(true, persist: false);
    } else {
      _deafened = false;
      // Restores what the microphone was doing beforehand. Unconditionally
      // unmuting here would switch on the microphone of someone who had
      // deliberately muted it before deafening.
      await setMicMuted(_micMutedBeforeDeafen, persist: false);
    }

    await _reapplyAudioState();
    onDeafenChanged?.call(deafened);
    notifyListeners();
  }

  bool _cameraOn = false;
  bool _screenSharing = false;

  bool get cameraOn => _cameraOn;
  bool get screenSharing => _screenSharing;

  /// Turns the camera on or off.
  ///
  /// Separate from joining on purpose: a voice channel should not light the
  /// camera indicator just because someone wanted to talk.
  Future<void> setCameraEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    try {
      await participant.setCameraEnabled(enabled);
      _cameraOn = enabled;
      notifyListeners();
    } catch (error, stack) {
      debugPrint('[voice] camera toggle failed: $error\n$stack');
      _error = 'Could not switch the camera on.';
      notifyListeners();
    }
  }

  /// Starts sharing the capture source [sourceId].
  ///
  /// [withSystemAudio] becomes `audio: true` in the underlying
  /// `getDisplayMedia` call, which flutter_webrtc turns into a WASAPI loopback
  /// track on Windows. LiveKit then publishes it as a separate
  /// `screenShareAudio` track, which is what the second per-user volume slider
  /// acts on.
  Future<void> startScreenShare(
    String sourceId, {
    required bool withSystemAudio,
  }) async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    try {
      await participant.setScreenShareEnabled(
        true,
        captureScreenAudio: withSystemAudio,
        screenShareCaptureOptions: lk.ScreenShareCaptureOptions(
          sourceId: sourceId,
        ),
      );
      _screenSharing = true;
      notifyListeners();
    } catch (error, stack) {
      debugPrint('[voice] screen share failed: $error\n$stack');
      _error = 'Could not start sharing.';
      notifyListeners();
    }
  }

  Future<void> stopScreenShare() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    try {
      // Also removes the screen-audio track; LiveKit tears down the pair.
      await participant.setScreenShareEnabled(false);
      _screenSharing = false;
      notifyListeners();
    } catch (error, stack) {
      debugPrint('[voice] stopping screen share failed: $error\n$stack');
    }
  }

  /// Everything currently worth drawing, screen shares first.
  ///
  /// Recomputed on read rather than cached: it changes only when LiveKit fires
  /// a track event, and those already trigger a notify, so caching would add a
  /// second source of truth for no gain.
  List<CallVideoTile> get videoTiles {
    final room = _room;
    if (room == null) return const [];

    final tiles = <CallVideoTile>[];

    void collect(
      lk.Participant participant,
      Iterable<lk.TrackPublication> publications, {
      required bool isLocal,
    }) {
      for (final publication in publications) {
        if (publication.kind != lk.TrackType.VIDEO) continue;
        final track = publication.track;
        if (track is! lk.VideoTrack) continue;
        // A muted camera still has a publication; drawing it would show a
        // frozen last frame rather than nothing.
        if (publication.muted) continue;

        final userId = matrixUserIdOf(participant.identity);
        tiles.add(
          CallVideoTile(
            key: '${participant.identity}|${publication.sid}',
            userId: userId,
            displayName: participant.name.isNotEmpty
                ? participant.name
                : userId,
            track: track,
            isScreenShare:
                publication.source == lk.TrackSource.screenShareVideo,
            isLocal: isLocal,
          ),
        );
      }
    }

    final local = room.localParticipant;
    if (local != null) {
      collect(local, local.trackPublications.values, isLocal: true);
    }
    for (final participant in room.remoteParticipants.values) {
      collect(participant, participant.trackPublications.values, isLocal: false);
    }

    // Shared screens are what people are looking at; faces are secondary.
    tiles.sort((a, b) {
      if (a.isScreenShare == b.isScreenShare) return 0;
      return a.isScreenShare ? -1 : 1;
    });
    return tiles;
  }

  /// Whether [userId] is currently sharing screen audio.
  ///
  /// Used to disable the screen-share volume slider rather than offer a control
  /// that silently does nothing.
  bool hasScreenAudio(String userId) {
    final room = _room;
    if (room == null) return false;
    for (final participant in room.remoteParticipants.values) {
      if (matrixUserIdOf(participant.identity) != userId) continue;
      for (final publication in participant.trackPublications.values) {
        if (publication.source == lk.TrackSource.screenShareAudio &&
            publication.track != null) {
          return true;
        }
      }
    }
    return false;
  }

  /// Called when the stored preferences changed.
  void onPrefsChanged() => unawaited(_reapplyAudioState());

  /// The **only** place remote audio tracks are touched.
  ///
  /// Deafen, a per-user local mute and a per-user volume are three independent
  /// inputs competing for one track. Applying them as three separate imperative
  /// operations produces ordering bugs that are miserable to track down —
  /// undeafening un-mutes someone the user had deliberately silenced, moving a
  /// slider quietly un-deafens one person, and so on.
  ///
  /// So no code path sets `enabled` or a volume directly. Everything changes an
  /// input and calls this, which recomputes the effective state from all three
  /// at once. Undeafening therefore does not "restore" anything: it flips one
  /// input and recomputes, and a locally muted user correctly stays silent.
  ///
  /// Calls are coalesced rather than queued. A continuous volume slider emits
  /// changes far faster than a round trip to the native audio backend, so
  /// running one pass per change would build an ever-growing backlog and leave
  /// the audio lagging seconds behind the thumb. Instead a pass in flight sets
  /// a dirty flag, and exactly one more pass runs afterwards with the final
  /// values — which is all anyone can hear anyway.
  Future<void> _reapplyAudioState() async {
    if (_reapplyInFlight) {
      _reapplyDirty = true;
      return;
    }
    _reapplyInFlight = true;
    try {
      do {
        _reapplyDirty = false;
        await _applyAudioOnce();
      } while (_reapplyDirty && !_disposed);
    } finally {
      _reapplyInFlight = false;
    }
  }

  Future<void> _applyAudioOnce() async {
    final room = _room;
    if (room == null) return;
    final prefs = readPrefs();

    for (final participant in room.remoteParticipants.values) {
      final userId = matrixUserIdOf(participant.identity);
      final deviceId = matrixDeviceIdOf(participant.identity);

      // Muting follows the person — it says "I do not want to hear this human",
      // which stays true when they switch machines. Volume follows the device,
      // because it calibrates one particular microphone: the same person is
      // quiet from a laptop and loud from a desk mic, and a per-person gain
      // would have to be re-adjusted on every device switch.
      final silenced = _deafened || prefs.forUser(userId).locallyMuted;
      final audio = prefs.audioFor(userId, deviceId);

      for (final publication in participant.trackPublications.values) {
        if (publication.kind != lk.TrackType.AUDIO) continue;
        final track = publication.track;
        if (track == null) continue;

        final isScreenAudio =
            publication.source == lk.TrackSource.screenShareAudio;
        final volume = isScreenAudio ? audio.screenVolume : audio.micVolume;
        final mediaTrack = track.mediaStreamTrack;

        try {
          // `enabled = false` rather than a zero volume: it is synchronous,
          // unambiguous, and leaves the stored gain intact so unmuting restores
          // the level the user had chosen instead of resetting it.
          mediaTrack.enabled = !silenced;
          if (!silenced) {
            // Linear gain where 1.0 is unchanged. The clamp is not paranoia: a
            // public flutter_webrtc report of "distortion on Windows" was
            // someone passing 80 where 0.8 was meant.
            await rtc.Helper.setVolume(
              volume.clamp(0.0, kMaxVolume),
              mediaTrack,
            );
          }
        } catch (error) {
          // The desktop backend looks tracks up by id and errors with
          // "Unable to find provided track" when it cannot; that surfaces here
          // rather than anywhere the user would see it, so it is called out
          // explicitly instead of being swallowed as a generic failure.
          debugPrint(
            '[voice] FAILED to apply volume for $userId/$deviceId: $error',
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Matrix side
  // ---------------------------------------------------------------------------

  /// Picks the SFU to use.
  ///
  /// Prefers whatever a live participant already advertises, so we join the
  /// call rather than starting a parallel one. Only when the room is empty do
  /// we fall back to our own homeserver's well-known service.
  LiveKitFocus? _resolveFocus(Room room) {
    for (final membership in liveMembershipsOf(room)) {
      final focus = membership.focusPreferred.firstOrNull;
      if (focus != null) return focus;
    }
    return _fallbackFocus(room.id);
  }

  /// Best-effort default when nobody is in the call yet.
  ///
  /// Derives the conventional Element Call service path from the homeserver
  /// URL. This is a guess by design — if it is wrong the token request fails
  /// with a clear error rather than connecting somewhere useless.
  LiveKitFocus? _fallbackFocus(String roomId) {
    final base = client.homeserver;
    if (base == null) return null;
    return LiveKitFocus(
      serviceUrl: '${base.origin}/livekit-jwt-service',
      alias: roomId,
    );
  }

  Future<void> _publishMembership(Room room, LiveKitFocus focus) async {
    final userId = client.userID!;
    final deviceId = client.deviceID!;

    await client.setRoomStateWithKey(
      room.id,
      kCallMemberEventType,
      MatrixRtcMembership.stateKeyFor(userId: userId, deviceId: deviceId),
      {
        'application': kCallApplication,
        'call_id': '',
        'scope': 'm.room',
        'device_id': deviceId,
        'membershipID': '$userId:$deviceId',
        'created_ts': DateTime.now().millisecondsSinceEpoch,
        'expires': kDefaultMembershipLifetime.inMilliseconds,
        'm.call.intent': 'audio',
        'foci_preferred': [focus.toJson()],
        'focus_active': {
          'type': 'livekit',
          'focus_selection': 'oldest_membership',
        },
      },
    );
  }

  /// Withdraws our membership by writing empty content.
  ///
  /// Not a redaction: MatrixRTC represents "left" as a state event with `{}`
  /// content, and that is what every other client checks for.
  Future<void> _clearMembership(String matrixRoomId) async {
    final userId = client.userID;
    final deviceId = client.deviceID;
    if (userId == null || deviceId == null) return;

    await client.setRoomStateWithKey(
      matrixRoomId,
      kCallMemberEventType,
      MatrixRtcMembership.stateKeyFor(userId: userId, deviceId: deviceId),
      const {},
    );
  }

  /// Asks the homeserver to withdraw our membership if we stop checking in.
  ///
  /// The counterpart to `_clearMembership`, for the exits that run no code:
  /// a Task Manager kill, a crash, a power cut. Best-effort — a homeserver
  /// without MSC4140 simply leaves us with `expires` as before. See
  /// `delayed_leave.dart`.
  Future<void> _armDelayedLeave(Room room, LiveKitFocus focus) async {
    final userId = client.userID;
    final deviceId = client.deviceID;
    if (userId == null || deviceId == null) return;

    final delayedLeave = DelayedLeave(
      client: client,
      roomId: room.id,
      stateKey: MatrixRtcMembership.stateKeyFor(
        userId: userId,
        deviceId: deviceId,
      ),
      // Only reached when the server withdrew us despite our still being in the
      // call, which means the state event it wrote is wrong and we have to put
      // it back rather than quietly disappear from the channel.
      onServerWithdrewMembership: () => _publishMembership(room, focus),
    );
    _delayedLeave = delayedLeave;
    await delayedLeave.arm();
  }

  void _scheduleMembershipRefresh(Room room, LiveKitFocus focus) {
    _refreshTimer?.cancel();
    final period = kDefaultMembershipLifetime - _membershipRefreshLead;
    _refreshTimer = Timer.periodic(period, (_) async {
      if (_disposed || !isInCall) return;
      try {
        await _publishMembership(room, focus);
      } catch (error, stack) {
        debugPrint('[voice] membership refresh failed: $error\n$stack');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // LiveKit side
  // ---------------------------------------------------------------------------

  void _attachListeners() {
    final listener = _listener;
    if (listener == null) return;

    listener
      ..on<lk.RoomDisconnectedEvent>((event) {
        debugPrint('[voice] LiveKit disconnected: ${event.reason}');
        if (_disposed) return;
        // The SFU dropped us. Tear the Matrix half down too, or we would keep
        // advertising a membership for a call we are no longer in.
        unawaited(leave());
      })
      ..on<lk.TrackSubscribedEvent>((event) {
        debugPrint(
          '[voice] subscribed ${event.publication.kind} from '
          '${event.participant.identity} enc=${event.publication.encryptionType}',
        );
        // The load-bearing re-application. A track that has just arrived is a
        // brand new object with gain 1.0 and `enabled` true — whether it
        // belongs to someone joining for the first time, someone rejoining, or
        // an ICE restart. Nothing in LiveKit carries the previous settings
        // across, so without this every reconnect quietly resets that person's
        // volume, which is exactly what "persistent across reconnects" means.
        unawaited(_reapplyAudioState());
        _safeNotify();
      })
      ..on<lk.TrackUnsubscribedEvent>((_) => _safeNotify())
      ..on<lk.ParticipantConnectedEvent>((event) {
        debugPrint('[voice] participant joined ${event.participant.identity}');
        _safeNotify();
      })
      ..on<lk.ParticipantDisconnectedEvent>((_) => _safeNotify())
      ..on<lk.TrackMutedEvent>((_) => _safeNotify())
      ..on<lk.TrackUnmutedEvent>((_) => _safeNotify())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _safeNotify());
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Capture options pinned to the chosen microphone.
  ///
  /// Selecting a device through `Hardware.selectAudioInput` is **not enough**
  /// on its own. That sets the native audio device module's recording endpoint,
  /// which is what makes output work, but the track is created by
  /// `getUserMedia` and takes its source from the capture constraints. With
  /// `deviceId` left null there is simply no constraint, so capture falls back
  /// to the platform default — a virtual cable here — and we publish silence
  /// while the settings dialog correctly shows the real microphone.
  ///
  /// `AudioCaptureOptions.toMediaConstraintsMap` turns this into
  /// `optional: [{sourceId: …}]` on native platforms.
  Future<lk.AudioCaptureOptions> _micCaptureOptions() async {
    final prefs = readPrefs();
    String? deviceId;
    try {
      final inputs = await lk.Hardware.instance.audioInputs();
      deviceId = matchDevice(prefs.inputDevice, inputs)?.deviceId;
    } catch (error, stack) {
      debugPrint('[voice] resolving microphone failed: $error\n$stack');
    }
    // Null means "no constraint", which is the right behaviour when the user
    // has not chosen a device yet.
    return lk.AudioCaptureOptions(deviceId: deviceId);
  }

  /// Applies the remembered microphone and output device.
  ///
  /// Necessary because livekit_client does **not** follow the operating
  /// system's default: `Hardware._internal` takes
  /// `devices.firstWhereOrNull(...)`, the first entry the platform enumerates.
  /// On a machine with a virtual audio cable installed that is typically the
  /// cable, so capture reads silence and playback goes into a loopback nobody
  /// is listening to — while connection, publication and subscription all
  /// report success.
  ///
  /// Safe to call outside a call, and safe to call when only the *output*
  /// changed: selecting a device is global state in livekit_client rather than
  /// a property of the room, and the microphone half below no-ops unless the
  /// input actually moved.
  Future<void> applyAudioDevices() async {
    final prefs = readPrefs();

    try {
      final inputs = await lk.Hardware.instance.audioInputs();
      final input = matchDevice(prefs.inputDevice, inputs);
      if (input != null) {
        await lk.Hardware.instance.selectAudioInput(input);
        debugPrint('[voice] microphone -> ${input.label}');
      }
    } catch (error, stack) {
      debugPrint('[voice] selecting microphone failed: $error\n$stack');
    }

    try {
      final outputs = await lk.Hardware.instance.audioOutputs();
      final output = matchDevice(prefs.outputDevice, outputs);
      if (output != null) {
        await lk.Hardware.instance.selectAudioOutput(output);
        debugPrint('[voice] output -> ${output.label}');
      }
    } catch (error, stack) {
      debugPrint('[voice] selecting output failed: $error\n$stack');
    }

    // `selectAudioInput` above moved the native device module's recording
    // index, which is not enough on its own: a capture already running was
    // opened by `getUserMedia` and keeps reading the old endpoint until the
    // track is recreated. So the live track has to be pointed at the new
    // device explicitly, or the setting appears to do nothing mid-call.
    final track = _room?.localParticipant
        ?.getTrackPublicationBySource(lk.TrackSource.microphone)
        ?.track;
    // Also the "nothing published yet" case, which is every call to this
    // during joining — the caller publishes the microphone right afterwards
    // with these same options.
    if (track is! lk.LocalAudioTrack) return;

    final deviceId = (await _micCaptureOptions()).deviceId;
    // Null means the user has not chosen a microphone, or the one they chose
    // is not plugged in. Neither is a reason to disturb a working capture.
    if (deviceId == null) return;

    try {
      // Deliberately **not** a mute/unmute cycle, which is what this used to
      // be. `setMicrophoneEnabled(false)` mutes the publication and signals
      // that to the SFU, so everyone else watched us go muted and back for a
      // device change they should never have noticed — and worse,
      // `setMicrophoneEnabled(true, audioCaptureOptions: …)` *ignores* those
      // options when a publication already exists, so the new device never
      // reached the track at all.
      //
      // `setDeviceId` updates the capture options and restarts the track in
      // place: `replaceTrack` on the existing sender, so the publication, its
      // sid and its frame cryptor all survive and nothing renegotiates. It
      // no-ops when the device is unchanged, and while muted it records the
      // choice without reopening the hardware — unmuting restarts from it.
      await track.setDeviceId(deviceId);
    } catch (error, stack) {
      debugPrint('[voice] switching microphone failed: $error\n$stack');
    }
  }

  /// Lists the audio hardware and what LiveKit picked.
  ///
  /// Worth its own log because livekit_client does **not** follow the operating
  /// system's default device. `Hardware._internal` selects
  /// `devices.firstWhereOrNull(...)` — literally the first entry the platform
  /// enumerates, which on Windows is frequently a virtual or unused endpoint.
  /// Playback then goes somewhere the user is not listening, and capture comes
  /// from a microphone that is not in front of them, while every other part of
  /// the stack reports success.
  ///
  /// That selection also runs in an `unawaited` future inside a singleton
  /// constructor, so it can still be unresolved at connect time — another
  /// reason to print what it actually ended up with rather than assume.
  Future<void> logAudioDevices() async {
    try {
      final inputs = await lk.Hardware.instance.audioInputs();
      final outputs = await lk.Hardware.instance.audioOutputs();

      debugPrint(
        '[voice] audio devices\n'
        '  selected in : ${lk.Hardware.instance.selectedAudioInput?.label}\n'
        '  selected out: ${lk.Hardware.instance.selectedAudioOutput?.label}',
      );
      for (final device in inputs) {
        debugPrint('  input       : ${device.label}  [${device.deviceId}]');
      }
      for (final device in outputs) {
        debugPrint('  output      : ${device.label}  [${device.deviceId}]');
      }
      if (inputs.isEmpty) {
        debugPrint('[voice] WARNING: no microphone enumerated at all');
      }
      if (outputs.isEmpty) {
        debugPrint('[voice] WARNING: no audio output enumerated at all');
      }
    } catch (error, stack) {
      debugPrint('[voice] enumerating audio devices failed: $error\n$stack');
    }
  }

  /// Dumps the state that decides whether audio can flow.
  ///
  /// Silence has several indistinguishable causes — wrong LiveKit room, mic
  /// never published, tracks arriving but encrypted, nobody actually connected
  /// — and all of them look identical from the UI. Each line below separates
  /// two of those cases, which is why this logs rather than guesses.
  void logDiagnostics(String phase) {
    final room = _room;
    if (room == null) {
      debugPrint('[voice] diagnostics ($phase): no room');
      return;
    }

    final local = room.localParticipant;
    debugPrint(
      '[voice] diagnostics ($phase)\n'
      '  connection : ${room.connectionState}\n'
      // The LiveKit room name is a SHA-256 of (matrix room, slot). If two
      // clients disagree on the slot they get different names here and never
      // meet, while everything else reports success.
      '  lk room    : ${room.name}\n'
      '  identity   : ${local?.identity}\n'
      '  remotes    : ${room.remoteParticipants.length}',
    );

    final localPublications =
        local?.trackPublications.values.toList() ??
        const <lk.LocalTrackPublication>[];
    for (final publication in localPublications) {
      debugPrint(
        '  local track: ${publication.kind} sid=${publication.sid} '
        'muted=${publication.muted} enc=${publication.encryptionType}',
      );
      // What the track is really capturing from, as opposed to what the
      // settings dialog claims — the two disagreeing is what publishes silence.
      //
      // `label` is useless here: flutter_webrtc's Windows backend returns a
      // bare track GUID rather than a device name. `getSettings()` is passed
      // straight through from the native getUserMedia response, so whatever
      // the platform knows about the chosen source shows up there.
      final track = publication.track;
      if (track != null) {
        debugPrint(
          '    settings: ${track.mediaStreamTrack.getSettings()}',
        );
      }
    }

    for (final participant in room.remoteParticipants.values) {
      debugPrint('  remote     : ${participant.identity}');
      for (final publication in participant.trackPublications.values) {
        // `subscribed=false` means we never asked for the track; an
        // `encryptionType` other than none means it arrives but we cannot
        // decode it without the E2EE keys. Those need opposite fixes.
        debugPrint(
          '    track    : ${publication.kind} sid=${publication.sid} '
          'subscribed=${publication.subscribed} muted=${publication.muted} '
          'enc=${publication.encryptionType}',
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    // Stops the heartbeat but deliberately leaves the scheduled withdrawal
    // standing. `_teardown` below cancels it properly if it gets that far; if
    // it does not, having the server withdraw us is precisely what we want.
    _delayedLeave?.dispose();
    // Best effort: without this a hard exit leaves our membership advertised
    // until it expires, showing us in a channel we are not in.
    unawaited(_teardown(_roomId));
    assert(() {
      liveInstanceCount--;
      return true;
    }());
    super.dispose();
  }
}

/// An error whose message is safe to show a user.
class _VoiceUserError implements Exception {
  _VoiceUserError(this.message);
  final String message;

  @override
  String toString() => message;
}
