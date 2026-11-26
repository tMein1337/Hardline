// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// flutter_webrtc builds a MediaStream from a getDisplayMedia answer with these
// two classes and exports neither. Our native side answers in exactly that
// shape (a stream id and a track it registered with flutter_webrtc), so the
// same classes wrap it. Pinned to the flutter_webrtc in pubspec.lock; a bump
// that moves them fails here at compile time, not at runtime.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_impl.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

/// One running screen share from the xdg-desktop-portal.
@immutable
class WaylandShare {
  const WaylandShare({required this.sessionId, required this.stream});

  /// Opaque, unique per share. Also the share's `sourceId` in the call.
  final String sessionId;

  /// A local stream with one video track, fed by the portal's PipeWire stream.
  final MediaStream stream;
}

/// Screen sharing on Linux Wayland, through `linux/screencast/`.
///
/// flutter_webrtc's bundled libwebrtc can only capture X11 screens, and on a
/// Wayland session it crashes listing them. Wayland has no way for an app to
/// enumerate or read the screen at all: the xdg-desktop-portal shows the
/// desktop's own picker and hands back a PipeWire stream of the choice. So on
/// Wayland there is no picker of ours, [start] opens the desktop's.
class WaylandScreencast {
  WaylandScreencast._();

  static const _methods = MethodChannel('hardline/screencast');
  static const _events = EventChannel('hardline/screencast/events');

  /// Whether this session should share through the portal rather than
  /// flutter_webrtc's own capturer. Platform only; [isAvailable] asks whether
  /// it can.
  static bool get applies =>
      !kIsWeb &&
      Platform.isLinux &&
      Platform.environment['XDG_SESSION_TYPE'] == 'wayland';

  /// Whether the app was built with portal support and the portal offers
  /// screen casting.
  static Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Shows the desktop's picker and starts sharing what was picked.
  ///
  /// Null when the user cancelled the picker. Throws [PlatformException] when
  /// the portal or PipeWire failed.
  static Future<WaylandShare?> start() async {
    final answer = await _methods.invokeMapMethod<String, dynamic>('start');
    if (answer == null) return null;
    final sessionId = answer['sessionId'] as String;
    final trackId = answer['trackId'] as String;
    final stream = MediaStreamNative(answer['streamId'] as String, 'local')
      ..setMediaTracks(const <dynamic>[], <dynamic>[
        <String, dynamic>{
          'id': trackId,
          'label': trackId,
          'kind': 'video',
          'enabled': true,
        },
      ]);
    return WaylandShare(sessionId: sessionId, stream: stream);
  }

  /// Stops the capture of [sessionId]. Unknown ids are ignored, so this is
  /// safe to call for any share's source id.
  static Future<void> stop(String sessionId) async {
    if (!isPortalSource(sessionId)) return;
    try {
      await _methods.invokeMethod<void>('stop', {'sessionId': sessionId});
    } on MissingPluginException {
      // Not built with the channel: nothing was ever started.
    }
  }

  /// Whether [sourceId] names a portal share rather than a flutter_webrtc
  /// capture source.
  static bool isPortalSource(String sourceId) => sourceId.startsWith('portal:');

  /// Session ids of shares that ended outside the app: the desktop's own
  /// "stop sharing" control, or the compositor dropping the stream.
  static Stream<String> get ended => _events
      .receiveBroadcastStream()
      .where((event) => event is Map && event['event'] == 'ended')
      .map((event) => (event as Map)['sessionId'] as String);
}
