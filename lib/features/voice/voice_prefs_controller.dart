import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/login_state_provider.dart';
import 'voice_prefs_state.dart';

/// Namespaced by Matrix user id.
///
/// The theme's flat key is fine because a theme belongs to the machine. These
/// belong to the *account*: a shared computer, or simply logging in as someone
/// else, must not inherit another person's per-user volumes and mutes.
String _prefsKeyFor(String userId) => 'voice_prefs_v1:$userId';

/// Owns the voice settings and persists them.
///
/// Structurally a copy of `ThemeController`: read synchronously from the
/// preferences injected in `main()`, write after updating state, and treat any
/// unreadable value as "use defaults" rather than letting it propagate.
class VoicePrefsController extends Notifier<VoicePrefsState> {
  @override
  VoicePrefsState build() {
    // loginStateProvider, not clientProvider: the Client instance never changes
    // for the life of the app, so watching it would pin this to whatever was
    // true before login — namely no user id, and therefore no settings, forever.
    ref.watch(loginStateProvider);

    final userId = ref.watch(clientProvider).userID;
    if (userId == null) return const VoicePrefsState.empty();

    final raw = ref.watch(prefsProvider).getString(_prefsKeyFor(userId));
    if (raw == null) return const VoicePrefsState.empty();

    try {
      return VoicePrefsState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (error, stack) {
      debugPrint('Ignoring unreadable voice prefs: $error\n$stack');
      return const VoicePrefsState.empty();
    }
  }

  Future<void> setInputDevice(AudioDeviceRef? device) =>
      _persist(state.copyWith(inputDevice: device));

  Future<void> setOutputDevice(AudioDeviceRef? device) =>
      _persist(state.copyWith(outputDevice: device));

  Future<void> setSelfMuted(bool muted) =>
      _persist(state.copyWith(selfMuted: muted));

  Future<void> setDeafened(bool deafened) =>
      _persist(state.copyWith(deafened: deafened));

  Future<void> setShareSystemAudio(bool share) =>
      _persist(state.copyWith(shareSystemAudio: share));

  /// [commit] false while a slider is being dragged: state updates so audio
  /// follows the thumb, but the write is deferred to `onChangeEnd`.
  ///
  /// This is the one deliberate departure from `ThemeController._persist`,
  /// which always writes because every change it makes is a discrete click.
  ///
  /// Volumes take a [deviceId] because they are a calibration of one particular
  /// microphone, not an opinion about the person — see [VoiceUserPrefs].
  Future<void> setUserMicVolume(
    String userId,
    String deviceId,
    double volume, {
    bool commit = true,
  }) => _updateDevice(
    userId,
    deviceId,
    (audio) => audio.copyWith(micVolume: volume.clamp(0.0, kMaxVolume)),
    commit: commit,
  );

  Future<void> setUserScreenVolume(
    String userId,
    String deviceId,
    double volume, {
    bool commit = true,
  }) => _updateDevice(
    userId,
    deviceId,
    (audio) => audio.copyWith(screenVolume: volume.clamp(0.0, kMaxVolume)),
    commit: commit,
  );

  /// Muting is per person, not per device: it says "I do not want to hear this
  /// human", which does not stop being true when they switch machines.
  Future<void> setUserLocallyMuted(String userId, bool muted) =>
      _updateUser(userId, (prefs) => prefs.copyWith(locallyMuted: muted));

  Future<void> resetUser(String userId) {
    final users = {...state.users}..remove(userId);
    return _persist(state.copyWith(users: users));
  }

  Future<void> _updateDevice(
    String userId,
    String deviceId,
    VoiceDeviceAudio Function(VoiceDeviceAudio) update, {
    bool commit = true,
  }) => _updateUser(
    userId,
    (prefs) {
      final devices = {...prefs.devices};
      final next = update(prefs.forDevice(deviceId));
      if (next.isDefault) {
        devices.remove(deviceId);
      } else {
        devices[deviceId] = next;
      }
      return prefs.copyWith(devices: devices);
    },
    commit: commit,
  );

  Future<void> _updateUser(
    String userId,
    VoiceUserPrefs Function(VoiceUserPrefs) update, {
    bool commit = true,
  }) {
    final users = {...state.users};
    final next = update(users[userId] ?? const VoiceUserPrefs());
    // Keep the map sparse: an entry back at its defaults is dropped rather
    // than stored, so resetting someone actually shrinks the blob.
    if (next.isDefault) {
      users.remove(userId);
    } else {
      users[userId] = next;
    }
    return _persist(state.copyWith(users: users), write: commit);
  }

  Future<void> _persist(VoicePrefsState next, {bool write = true}) async {
    // State first so the change is audible immediately; the write can lag.
    state = next;
    if (!write) return;

    final userId = ref.read(clientProvider).userID;
    if (userId == null) return;
    await ref
        .read(prefsProvider)
        .setString(_prefsKeyFor(userId), jsonEncode(next.toJson()));
  }
}

final voicePrefsProvider =
    NotifierProvider<VoicePrefsController, VoicePrefsState>(
      VoicePrefsController.new,
    );
