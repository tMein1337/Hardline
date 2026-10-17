// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// What the app sends the overlay, and what the overlay sends back.
///
/// The two live in the same process but in **different Dart isolates**, one per
/// Flutter engine, so nothing can be shared by reference — not the call
/// controller, not the theme, not an avatar already decoded. Everything the HUD
/// draws has to arrive as bytes.
///
/// That is also why there are two kinds of message rather than one. A full
/// snapshot carries avatar images, which are kilobytes; who is speaking changes
/// several times a second. Sending the images at speech rate would be sending a
/// few hundred kilobytes a second between two isolates to redraw a ring.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'overlay_layout.dart';

/// One person as the overlay knows them.
///
/// No `mxc://` and no access token: the overlay isolate has no Matrix client
/// and could not resolve one. The app side fetches the thumbnail once and sends
/// the bytes.
@immutable
class OverlayPerson {
  const OverlayPerson({
    required this.userId,
    required this.name,
    required this.avatar,
  });

  factory OverlayPerson.fromJson(Map<String, Object?> json) {
    final avatar = json['avatar'];
    return OverlayPerson(
      userId: json['userId'] is String ? json['userId']! as String : '',
      name: json['name'] is String ? json['name']! as String : '',
      avatar: avatar is String && avatar.isNotEmpty
          ? _decodeAvatar(avatar)
          : null,
    );
  }

  final String userId;

  /// Already through `displaySafeName` on the app side. The overlay draws it
  /// as given, because the sanitiser belongs at the point a name is read out of
  /// the SDK, not at every `Text` that shows one.
  final String name;

  /// An encoded image — whatever the homeserver served for the thumbnail.
  /// Null falls back to initials, exactly as `MxAvatar` does.
  final Uint8List? avatar;

  Map<String, Object?> toJson() => {
    'userId': userId,
    'name': name,
    if (avatar != null) 'avatar': base64Encode(avatar!),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlayPerson &&
          userId == other.userId &&
          name == other.name &&
          _sameBytes(avatar, other.avatar);

  @override
  int get hashCode => Object.hash(userId, name, avatar?.length);
}

/// The colours the HUD needs, resolved from the user's theme by the app.
///
/// Sent rather than looked up, so the overlay matches a custom theme without
/// the overlay isolate having to load the theme system, the preferences and the
/// palette files a second time.
@immutable
class OverlayPalette {
  const OverlayPalette({
    required this.speakingRing,
    required this.text,
    required this.plate,
  });

  factory OverlayPalette.fromJson(Map<String, Object?> json) => OverlayPalette(
    speakingRing: json['ring'] is int ? json['ring']! as int : 0xFFFF7A18,
    text: json['text'] is int ? json['text']! as int : 0xFFFFFFFF,
    plate: json['plate'] is int ? json['plate']! as int : 0xFF08080A,
  );

  /// The colour the runner turns into a hole through to whatever is behind.
  ///
  /// **Derived from [plate] rather than fixed**, and that is the whole point.
  ///
  /// The key used to be pure magenta, on the traditional reasoning that a
  /// chroma key should be the colour least likely to appear in the content.
  /// That is right for video and wrong here, because of antialiasing: a curved
  /// or fractionally-positioned edge blends into the key, so every rounded
  /// corner in the HUD wore a thin magenta line. Chasing pixel alignment does
  /// not fix it either — text is fractionally wide, and on a display at 125%
  /// a whole logical pixel is not a whole device pixel.
  ///
  /// So instead of making the fringe rare, make it invisible: key on a colour
  /// one step from the plate. Edges then blend plate-to-almost-plate, which
  /// cannot be seen, in a light palette as well as a dark one — the day
  /// palette's plate is white, so any fixed key would have fringed *dark*
  /// there.
  ///
  /// The cost is the opposite risk, and it is small: a pixel in somebody's
  /// avatar exactly equal to this becomes a hole. One pixel, showing the game,
  /// in a colour a shade from the surrounding plate.
  int get chromaKey => plate ^ 0x00010101;

  /// ARGB, because that is what `Color` takes on the far side.
  final int speakingRing;
  final int text;

  /// What the name sits on, so it stays readable over a bright game.
  ///
  /// **Must be opaque**, like every other colour here. The overlay window is
  /// colour-keyed, so a colour carrying alpha blends towards the key rather
  /// than towards the game behind it. See [chromaKey].
  final int plate;

  Map<String, Object?> toJson() => {
    'ring': speakingRing,
    'text': text,
    'plate': plate,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlayPalette &&
          speakingRing == other.speakingRing &&
          text == other.text &&
          plate == other.plate;

  @override
  int get hashCode => Object.hash(speakingRing, text, plate);
}

/// Everything the HUD needs, minus who is talking at this instant.
@immutable
class OverlaySnapshot {
  const OverlaySnapshot({
    required this.people,
    required this.layout,
    required this.palette,
    required this.editing,
  });

  factory OverlaySnapshot.fromJson(Map<String, Object?> json) {
    final rawPeople = json['people'];
    final people = <OverlayPerson>[];
    if (rawPeople is List) {
      for (final entry in rawPeople) {
        if (entry is Map) {
          people.add(OverlayPerson.fromJson(entry.cast<String, Object?>()));
        }
      }
    }

    final rawLayout = json['layout'];
    final rawPalette = json['palette'];

    return OverlaySnapshot(
      people: people,
      layout: rawLayout is Map
          ? OverlayLayout.fromJson(rawLayout.cast<String, Object?>())
          : const OverlayLayout(id: 'default', name: 'Default'),
      palette: rawPalette is Map
          ? OverlayPalette.fromJson(rawPalette.cast<String, Object?>())
          : const OverlayPalette(
              speakingRing: 0xFFFF7A18,
              text: 0xFFFFFFFF,
              plate: 0xFF08080A,
            ),
      editing: json['editing'] is bool ? json['editing']! as bool : false,
    );
  }

  final List<OverlayPerson> people;
  final OverlayLayout layout;
  final OverlayPalette palette;

  /// Edit mode: the HUD accepts the mouse, draws its own chrome, and shows
  /// stand-ins when the call is empty so there is something to drag.
  final bool editing;

  Map<String, Object?> toJson() => {
    'kind': 'snapshot',
    'people': [for (final person in people) person.toJson()],
    'layout': layout.toJson(),
    'palette': palette.toJson(),
    'editing': editing,
  };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlaySnapshot &&
          listEquals(people, other.people) &&
          layout == other.layout &&
          palette == other.palette &&
          editing == other.editing;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(people), layout, palette, editing);
}

/// The hot path: who is audible, and nothing else.
@immutable
class OverlaySpeaking {
  const OverlaySpeaking(this.userIds);

  factory OverlaySpeaking.fromJson(Map<String, Object?> json) {
    final raw = json['ids'];
    return OverlaySpeaking({
      if (raw is List)
        for (final id in raw)
          if (id is String) id,
    });
  }

  final Set<String> userIds;

  String encode() => jsonEncode({'kind': 'speaking', 'ids': userIds.toList()});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlaySpeaking && setEquals(userIds, other.userIds);

  @override
  int get hashCode => Object.hashAllUnordered(userIds);
}

/// What the overlay sends back: a layout the user dragged into place.
@immutable
class OverlayEdit {
  const OverlayEdit(this.layout);

  factory OverlayEdit.fromJson(Map<String, Object?> json) {
    final raw = json['layout'];
    return OverlayEdit(
      OverlayLayout.fromJson(
        raw is Map ? raw.cast<String, Object?>() : const {},
      ),
    );
  }

  final OverlayLayout layout;

  String encode() => jsonEncode({'kind': 'edit', 'layout': layout.toJson()});
}

/// Reads whichever kind of message arrived, or null if it was not one of ours.
///
/// Total: a malformed payload is dropped, never thrown. The channel is not a
/// trust boundary — both ends are this app — but a version skew during a hot
/// reload should leave a stale HUD rather than a crashed engine.
Object? decodeOverlayMessage(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final json = decoded.cast<String, Object?>();
    return switch (json['kind']) {
      'snapshot' => OverlaySnapshot.fromJson(json),
      'speaking' => OverlaySpeaking.fromJson(json),
      'edit' => OverlayEdit.fromJson(json),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

Uint8List? _decodeAvatar(String encoded) {
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}

bool _sameBytes(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
