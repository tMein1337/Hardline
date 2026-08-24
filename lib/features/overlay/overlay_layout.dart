// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Smallest and largest avatar the overlay will draw, in logical pixels.
///
/// The floor is where a face stops being recognisable at a glance across a
/// room; the ceiling is where the HUD stops being a HUD and starts being a
/// window over the game.
const kMinOverlayAvatar = 20.0;
const kMaxOverlayAvatar = 96.0;

/// One arrangement of the overlay, with a name.
///
/// Named and identified rather than anonymous, because a layout is not owned by
/// the game it was made for: several executables point at the same one, so a
/// new game can adopt an existing HUD instead of being built from nothing. That
/// is the whole reason this has an [id] and a [name] at all.
///
/// Positions are **fractions of the monitor**, not pixels. A layout made at
/// 2560x1440 has to land in the same place when the same monitor is driven at
/// 1920x1080 for a game, and pixels do not survive that.
@immutable
class OverlayLayout {
  const OverlayLayout({
    required this.id,
    required this.name,
    this.x = 0.02,
    this.y = 0.08,
    this.horizontal = false,
    this.avatarSize = 40,
    this.showNames = true,
    this.idleOpacity = 0,
  });

  factory OverlayLayout.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    return OverlayLayout(
      id: id is String && id.isNotEmpty ? id : 'default',
      name: name is String && name.isNotEmpty ? name : 'Overlay',
      x: _fraction(json['x'], 0.02),
      y: _fraction(json['y'], 0.08),
      horizontal: json['horizontal'] is bool
          ? json['horizontal']! as bool
          : false,
      avatarSize: _clamped(
        json['avatarSize'],
        kMinOverlayAvatar,
        kMaxOverlayAvatar,
        40,
      ),
      showNames: json['showNames'] is bool ? json['showNames']! as bool : true,
      idleOpacity: _fraction(json['idleOpacity'], 0),
    );
  }

  final String id;
  final String name;

  /// Where the roster's top-left corner sits, as a fraction of the monitor.
  final double x;
  final double y;

  /// Whether people are listed across rather than down.
  final bool horizontal;

  final double avatarSize;
  final bool showNames;

  /// How visible somebody is while they are **not** speaking.
  ///
  /// Zero by default, which is the point of the thing: a quiet call leaves
  /// nothing at all over the game, and somebody talking appears. Anyone who
  /// would rather see who is in the channel at all times can raise it.
  final double idleOpacity;

  OverlayLayout copyWith({
    String? name,
    double? x,
    double? y,
    bool? horizontal,
    double? avatarSize,
    bool? showNames,
    double? idleOpacity,
  }) => OverlayLayout(
    id: id,
    name: name ?? this.name,
    x: x ?? this.x,
    y: y ?? this.y,
    horizontal: horizontal ?? this.horizontal,
    avatarSize: avatarSize ?? this.avatarSize,
    showNames: showNames ?? this.showNames,
    idleOpacity: idleOpacity ?? this.idleOpacity,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'x': x,
    'y': y,
    'horizontal': horizontal,
    'avatarSize': avatarSize,
    'showNames': showNames,
    'idleOpacity': idleOpacity,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlayLayout &&
          id == other.id &&
          name == other.name &&
          x == other.x &&
          y == other.y &&
          horizontal == other.horizontal &&
          avatarSize == other.avatarSize &&
          showNames == other.showNames &&
          idleOpacity == other.idleOpacity;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    x,
    y,
    horizontal,
    avatarSize,
    showNames,
    idleOpacity,
  );
}

/// A global chord, in the Win32 terms the runner needs.
///
/// Stored as `MOD_*` and virtual-key numbers rather than as anything friendlier
/// because that is what `RegisterHotKey` takes, and translating twice is two
/// places for a mapping to be wrong.
@immutable
class OverlayHotkey {
  const OverlayHotkey({required this.modifiers, required this.key});

  /// Nothing bound. Registering this is a no-op rather than an error.
  const OverlayHotkey.none() : modifiers = 0, key = 0;

  factory OverlayHotkey.fromJson(Map<String, Object?> json) => OverlayHotkey(
    modifiers: json['modifiers'] is int ? json['modifiers']! as int : 0,
    key: json['key'] is int ? json['key']! as int : 0,
  );

  /// A bitmask of `MOD_ALT` (1), `MOD_CONTROL` (2), `MOD_SHIFT` (4).
  final int modifiers;

  /// A Win32 virtual-key code. Zero means unbound.
  final int key;

  bool get isBound => key != 0;

  Map<String, Object?> toJson() => {'modifiers': modifiers, 'key': key};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlayHotkey && modifiers == other.modifiers && key == other.key;

  @override
  int get hashCode => Object.hash(modifiers, key);
}

/// Win32 modifier bits, so nothing has to remember which number is which.
abstract final class HotkeyModifier {
  static const alt = 1;
  static const control = 2;
  static const shift = 4;
}

double _fraction(Object? raw, double fallback) =>
    _clamped(raw, 0, 1, fallback);

/// Reads a number that a corrupt or hand-edited blob may have made nonsense.
///
/// Out-of-range values are clamped rather than rejected: a layout that is
/// merely wrong should snap back onto the screen, not refuse to load and take
/// every other layout in the file with it.
double _clamped(Object? raw, double min, double max, double fallback) {
  final value = raw is num ? raw.toDouble() : null;
  if (value == null || !value.isFinite) return fallback;
  return value.clamp(min, max);
}
