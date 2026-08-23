// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Upper bound for any stored or applied gain.
const double kMaxVolume = 2.0;

/// A remembered audio device.
///
/// Both id and label are stored on purpose. Windows device ids are GUIDs that
/// usually survive reboots, but they change when a device is moved to another
/// USB port or its driver is reinstalled — at which point matching by label
/// still finds the user's headphones instead of silently falling back to
/// whatever LiveKit would have picked.
@immutable
class AudioDeviceRef {
  const AudioDeviceRef({required this.deviceId, required this.label});

  final String deviceId;
  final String label;

  Map<String, Object?> toJson() => {'id': deviceId, 'label': label};

  static AudioDeviceRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final label = json['label'];
    if (id is! String || id.isEmpty) return null;
    return AudioDeviceRef(
      deviceId: id,
      label: label is String ? label : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDeviceRef &&
          deviceId == other.deviceId &&
          label == other.label;

  @override
  int get hashCode => Object.hash(deviceId, label);
}

/// Volumes for one *device* of one person.
///
/// Keyed per device rather than per person because volume is a calibration, not
/// an opinion: the same colleague is quiet from their laptop's built-in
/// microphone and loud from their desk mic, so a single per-person value would
/// have to be re-adjusted on every device switch. Storing it per device means
/// setting it once per device and never again.
@immutable
class VoiceDeviceAudio {
  const VoiceDeviceAudio({this.micVolume = 1.0, this.screenVolume = 1.0});

  /// Linear gain, 1.0 = unchanged. Clamped on parse, see [fromJson].
  final double micVolume;
  final double screenVolume;

  bool get isDefault => micVolume == 1.0 && screenVolume == 1.0;

  VoiceDeviceAudio copyWith({double? micVolume, double? screenVolume}) =>
      VoiceDeviceAudio(
        micVolume: micVolume ?? this.micVolume,
        screenVolume: screenVolume ?? this.screenVolume,
      );

  Map<String, Object?> toJson() => {'mic': micVolume, 'screen': screenVolume};

  /// Clamps at parse time rather than at playback.
  ///
  /// A hand-edited or corrupted `"mic": 50` would otherwise be applied as a
  /// 50x gain the instant a call connects — loud enough to hurt. Clamping here
  /// means no code path downstream can produce that, whatever it does.
  static VoiceDeviceAudio fromJson(Object? json) {
    if (json is! Map) return const VoiceDeviceAudio();
    double read(String key) {
      final value = json[key];
      if (value is num) return value.toDouble().clamp(0.0, kMaxVolume);
      return 1.0;
    }

    return VoiceDeviceAudio(
      micVolume: read('mic'),
      screenVolume: read('screen'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceDeviceAudio &&
          micVolume == other.micVolume &&
          screenVolume == other.screenVolume;

  @override
  int get hashCode => Object.hash(micVolume, screenVolume);
}

/// What we remember about one person.
///
/// Note the split: [locallyMuted] belongs to the *person* while [devices] holds
/// per-device volumes. Muting someone is a statement about them — it should
/// hold whichever machine they happen to be on — whereas a gain is a property
/// of the microphone at the other end.
@immutable
class VoiceUserPrefs {
  const VoiceUserPrefs({this.locallyMuted = false, this.devices = const {}});

  final bool locallyMuted;

  /// Matrix device id to its volumes. Sparse: devices left at their defaults
  /// are not stored.
  final Map<String, VoiceDeviceAudio> devices;

  bool get isDefault => !locallyMuted && devices.isEmpty;

  /// Volumes for one device.
  ///
  /// Unknown devices deliberately start at 1.0 rather than inheriting from
  /// another device of the same person: inheriting a boost calibrated for a
  /// different microphone is precisely the mis-calibration this per-device
  /// design exists to avoid, and arriving loud is worse than arriving neutral.
  VoiceDeviceAudio forDevice(String deviceId) =>
      devices[deviceId] ?? const VoiceDeviceAudio();

  VoiceUserPrefs copyWith({
    bool? locallyMuted,
    Map<String, VoiceDeviceAudio>? devices,
  }) => VoiceUserPrefs(
    locallyMuted: locallyMuted ?? this.locallyMuted,
    devices: devices ?? this.devices,
  );

  Map<String, Object?> toJson() => {
    if (locallyMuted) 'muted': true,
    'devices': {
      for (final entry in devices.entries)
        if (!entry.value.isDefault) entry.key: entry.value.toJson(),
    },
  };

  static VoiceUserPrefs fromJson(Object? json) {
    if (json is! Map) return const VoiceUserPrefs();
    final rawDevices = json['devices'];
    return VoiceUserPrefs(
      locallyMuted: json['muted'] == true,
      devices: rawDevices is Map
          ? {
              for (final entry in rawDevices.entries)
                if (entry.key is String)
                  entry.key as String: VoiceDeviceAudio.fromJson(entry.value),
            }
          // A v1 blob stored `mic`/`screen` directly on the user. The mute flag
          // still means what it did, but those volumes were calibrated against
          // "whatever device that person happened to be on" and cannot be
          // attributed to one, so they are dropped rather than misapplied.
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceUserPrefs &&
          locallyMuted == other.locallyMuted &&
          mapEquals(devices, other.devices);

  @override
  int get hashCode =>
      Object.hash(locallyMuted, Object.hashAllUnordered(devices.entries.map(
        (e) => Object.hash(e.key, e.value),
      )));
}

/// The quietest threshold the slider offers, in dB.
///
/// The tap's own floor, and not a round number chosen for looks. The first
/// version stopped at -80 on the theory that the last twenty were only ever a
/// silent room — which was wrong. The reading comes from one FFT band averaged
/// across 10Hz to 8kHz, so speech energy is divided among mostly empty high
/// bins and lands far below the broadband level it feels like; on a dynamic
/// microphone ordinary talking measured about -90. A floor above somebody's
/// voice is a threshold they cannot reach, and a gate that never opens.
const kMinThresholdDb = -100.0;

/// The loudest threshold the slider offers, in dB.
///
/// Not a design choice: the visualizer the tap reads clamps its own input here,
/// so nothing above -30 dB can be told from -30 dB.
const kMaxThresholdDb = -30.0;

/// Where the threshold starts, in dB.
///
/// Low, deliberately. Until somebody has watched the meter this only decides
/// when their own avatar rings, and a ring that is too eager is a far smaller
/// annoyance than one that never appears — which is the complaint that started
/// this whole feature.
const kDefaultThresholdDb = -95.0;

/// How much the microphone reading can be trimmed up, in dB.
///
/// Not a gain on the audio — nothing here changes how loud anybody sounds; see
/// `audio_level_sampler.dart`. It moves the *measurement* so a quiet microphone
/// lands somewhere the threshold slider has room to work, instead of pinned
/// against the bottom of the scale where a decibel of travel is most of the
/// useful range.
const kMaxMicGainDb = 60.0;

/// Everything the voice feature remembers between runs.
///
/// Mirrors `AppThemeState` in shape deliberately: immutable, JSON round-trip,
/// and a `fromJson` that degrades to defaults rather than throwing, so a
/// corrupt preference can never stop the app from starting.
@immutable
class VoicePrefsState {
  const VoicePrefsState({
    this.selfMuted = false,
    this.deafened = false,
    this.shareSystemAudio = false,
    this.micThresholdDb = kDefaultThresholdDb,
    this.micGainDb = 0,
    this.noiseGate = false,
    this.inputDevice,
    this.outputDevice,
    this.users = const {},
  });

  const VoicePrefsState.empty() : this();

  final bool selfMuted;
  final bool deafened;

  /// Whether a screen share also carries the shared application's audio.
  ///
  /// Off by default, and deliberately a setting rather than a prompt on every
  /// share. Capturing system audio while listening on speakers can feed the
  /// other participants' voices back to them, and that is a nasty surprise to
  /// spring on someone mid-call — better a choice made once, deliberately.
  final bool shareSystemAudio;

  /// The microphone level, in dB, at which you count as speaking.
  ///
  /// Always in force: it is what lights your own avatar's ring, whether or not
  /// [noiseGate] is on. LiveKit's own answer to "is this person speaking" is
  /// decided by the SFU with a threshold no client can reach, and it is set
  /// high enough that ordinary speech does not reliably trip it — which is the
  /// whole reason this exists.
  ///
  /// Decibels rather than an abstract fraction so the number on the slider is
  /// the number on the meter, and so it means the same thing tomorrow.
  final double micThresholdDb;

  /// Decibels added to the microphone reading before anything looks at it.
  ///
  /// A trim on the *measurement*, not on the audio. It exists because the
  /// reading is systematically low — see [kMinThresholdDb] — so without it a
  /// quiet microphone spends the whole scale in its bottom few decibels.
  final double micGainDb;

  /// Whether [micThreshold] also stops audio being sent.
  ///
  /// Off by default, and that is not timidity: a threshold that suits one
  /// microphone will cut somebody else off mid-sentence, and being inaudible
  /// is a failure you cannot notice yourself. Turning it on is a decision made
  /// while watching the meter, which is where the setting lives.
  final bool noiseGate;

  /// Null means "whatever the platform picks".
  ///
  /// Worth setting explicitly: livekit_client does not follow the OS default,
  /// it takes the first enumerated device, which is regularly a virtual cable.
  final AudioDeviceRef? inputDevice;
  final AudioDeviceRef? outputDevice;

  /// Matrix user id to what we remember about them.
  ///
  /// Sparse — only users who differ from the defaults are stored, the same way
  /// `AppThemeState.overrides` is sparse. Otherwise this grows one entry per
  /// person ever met in a call and never shrinks.
  final Map<String, VoiceUserPrefs> users;

  /// Never null, so callers do not have to null-check every lookup.
  VoiceUserPrefs forUser(String userId) =>
      users[userId] ?? const VoiceUserPrefs();

  /// Convenience for the common lookup: this person, on this device.
  VoiceDeviceAudio audioFor(String userId, String deviceId) =>
      forUser(userId).forDevice(deviceId);

  VoicePrefsState copyWith({
    bool? selfMuted,
    bool? deafened,
    bool? shareSystemAudio,
    double? micThresholdDb,
    double? micGainDb,
    bool? noiseGate,
    AudioDeviceRef? inputDevice,
    AudioDeviceRef? outputDevice,
    Map<String, VoiceUserPrefs>? users,
  }) => VoicePrefsState(
    selfMuted: selfMuted ?? this.selfMuted,
    deafened: deafened ?? this.deafened,
    shareSystemAudio: shareSystemAudio ?? this.shareSystemAudio,
    micThresholdDb: micThresholdDb ?? this.micThresholdDb,
    micGainDb: micGainDb ?? this.micGainDb,
    noiseGate: noiseGate ?? this.noiseGate,
    inputDevice: inputDevice ?? this.inputDevice,
    outputDevice: outputDevice ?? this.outputDevice,
    users: users ?? this.users,
  );

  Map<String, Object?> toJson() => {
    'version': 2,
    'selfMuted': selfMuted,
    'deafened': deafened,
    'shareSystemAudio': shareSystemAudio,
    'micThresholdDb': micThresholdDb,
    'micGainDb': micGainDb,
    'noiseGate': noiseGate,
    if (inputDevice != null) 'inputDevice': inputDevice!.toJson(),
    if (outputDevice != null) 'outputDevice': outputDevice!.toJson(),
    'users': {
      for (final entry in users.entries)
        if (!entry.value.isDefault) entry.key: entry.value.toJson(),
    },
  };

  /// Tolerant of anything: an unknown `version`, wrong types, missing keys.
  static VoicePrefsState fromJson(Map<String, Object?> json) {
    final rawUsers = json['users'];
    return VoicePrefsState(
      selfMuted: json['selfMuted'] == true,
      deafened: json['deafened'] == true,
      shareSystemAudio: json['shareSystemAudio'] == true,
      // A stored threshold outside the slider's range would be a gate nobody
      // could reopen from the settings screen.
      micThresholdDb: switch (json['micThresholdDb']) {
        final num value => value.toDouble().clamp(
          kMinThresholdDb,
          kMaxThresholdDb,
        ),
        _ => kDefaultThresholdDb,
      },
      micGainDb: switch (json['micGainDb']) {
        final num value => value.toDouble().clamp(0.0, kMaxMicGainDb),
        _ => 0.0,
      },
      noiseGate: json['noiseGate'] == true,
      inputDevice: AudioDeviceRef.fromJson(json['inputDevice']),
      outputDevice: AudioDeviceRef.fromJson(json['outputDevice']),
      users: rawUsers is Map
          ? {
              for (final entry in rawUsers.entries)
                if (entry.key is String)
                  entry.key as String: VoiceUserPrefs.fromJson(entry.value),
            }
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoicePrefsState &&
          selfMuted == other.selfMuted &&
          deafened == other.deafened &&
          shareSystemAudio == other.shareSystemAudio &&
          micThresholdDb == other.micThresholdDb &&
          micGainDb == other.micGainDb &&
          noiseGate == other.noiseGate &&
          inputDevice == other.inputDevice &&
          outputDevice == other.outputDevice &&
          mapEquals(users, other.users);

  @override
  int get hashCode => Object.hash(
    selfMuted,
    deafened,
    shareSystemAudio,
    micThresholdDb,
    micGainDb,
    noiseGate,
    inputDevice,
    outputDevice,
    Object.hashAllUnordered(
      users.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
