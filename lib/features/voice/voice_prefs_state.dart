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
    AudioDeviceRef? inputDevice,
    AudioDeviceRef? outputDevice,
    Map<String, VoiceUserPrefs>? users,
  }) => VoicePrefsState(
    selfMuted: selfMuted ?? this.selfMuted,
    deafened: deafened ?? this.deafened,
    shareSystemAudio: shareSystemAudio ?? this.shareSystemAudio,
    inputDevice: inputDevice ?? this.inputDevice,
    outputDevice: outputDevice ?? this.outputDevice,
    users: users ?? this.users,
  );

  Map<String, Object?> toJson() => {
    'version': 2,
    'selfMuted': selfMuted,
    'deafened': deafened,
    'shareSystemAudio': shareSystemAudio,
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
          inputDevice == other.inputDevice &&
          outputDevice == other.outputDevice &&
          mapEquals(users, other.users);

  @override
  int get hashCode => Object.hash(
    selfMuted,
    deafened,
    shareSystemAudio,
    inputDevice,
    outputDevice,
    Object.hashAllUnordered(
      users.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
