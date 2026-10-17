// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Smallest and largest avatar the overlay will draw, in logical pixels.
///
/// The floor is where a face stops being recognisable at a glance across a
/// room; the ceiling is where the HUD stops being a HUD and starts being a
/// window over the game.
/// How visible the HUD is once nobody has spoken for the linger.
///
/// **Not zero, which it used to be.** Zero is a real answer — "show me only
/// who is talking" — but it is a poor default now that the fade is applied to
/// the window rather than to the individual entries: at zero the entire
/// overlay disappears, so switching the feature on and looking at the screen
/// shows nothing at all, which is indistinguishable from it being broken.
///
/// Dim enough to sit over a game without competing with it, bright enough that
/// the feature is visibly doing something.
const kDefaultIdleOpacity = 0.35;

/// How visible the HUD is while somebody is talking.
///
/// Full, because that is the moment the overlay exists for. It is a setting
/// rather than a constant because the whole point of the thing is to sit over
/// a game somebody is trying to see, and "loud enough to notice" is a
/// judgement about that game, not about the HUD — a bright overlay over a dark
/// map is a distraction where the same overlay over a bright one is barely
/// there.
const kDefaultActiveOpacity = 1.0;

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
    this.idleOpacity = kDefaultIdleOpacity,
    this.activeOpacity = kDefaultActiveOpacity,
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
      // `activeOpacity` is the marker for when this layout was written.
      //
      // A layout saved before the fade moved to the window has no such key,
      // and its `idleOpacity` means something the current code cannot honour.
      // It used to be the opacity of the *quiet entries*, with the speaker
      // still coming up to full over them — so zero meant "show me only who
      // is talking". The fade is now applied to the whole window, because a
      // layered window has no per-pixel alpha to give the entries, and the
      // same zero means "show nothing at all, ever, until somebody talks".
      //
      // Those are different promises, and silently keeping the number while
      // changing what it does is how somebody ends up with a feature that is
      // switched on and invisible. A zero written under the old meaning is
      // migrated once; a zero written since is a real choice and is kept.
      idleOpacity: _migratedIdleOpacity(json),
      activeOpacity: _fraction(json['activeOpacity'], kDefaultActiveOpacity),
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

  /// See [kDefaultActiveOpacity].
  ///
  /// Deliberately not constrained to be above [idleOpacity]. Setting it lower
  /// is strange but coherent — "get out of the way when the conversation picks
  /// up" — and refusing it would be the app deciding it knows better about
  /// somebody else's screen.
  final double activeOpacity;

  OverlayLayout copyWith({
    String? name,
    double? x,
    double? y,
    bool? horizontal,
    double? avatarSize,
    bool? showNames,
    double? idleOpacity,
    double? activeOpacity,
  }) => OverlayLayout(
    id: id,
    name: name ?? this.name,
    x: x ?? this.x,
    y: y ?? this.y,
    horizontal: horizontal ?? this.horizontal,
    avatarSize: avatarSize ?? this.avatarSize,
    showNames: showNames ?? this.showNames,
    idleOpacity: idleOpacity ?? this.idleOpacity,
    activeOpacity: activeOpacity ?? this.activeOpacity,
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
    'activeOpacity': activeOpacity,
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
          idleOpacity == other.idleOpacity &&
          activeOpacity == other.activeOpacity;

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
    activeOpacity,
  );
}

/// [idleOpacity] from stored JSON, migrating a pre-window-alpha zero.
///
/// See the note at the call site. The test is the *absence* of
/// `activeOpacity`, which only layouts written before the change can have —
/// so this runs at most once per layout and cannot touch a choice made since.
double _migratedIdleOpacity(Map<String, Object?> json) {
  final stored = _fraction(json['idleOpacity'], kDefaultIdleOpacity);
  final writtenBeforeTheChange = json['activeOpacity'] is! num;
  if (writtenBeforeTheChange && stored == 0) return kDefaultIdleOpacity;
  return stored;
}

double _fraction(Object? raw, double fallback) => _clamped(raw, 0, 1, fallback);

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
