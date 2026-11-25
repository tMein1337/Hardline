// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/app_info.dart';
import 'notification_content.dart';

/// Where notifications go. An interface so the decision of *whether* to
/// notify can be tested without an operating system to show anything.
abstract interface class NotificationSink {
  Future<void> show(NotificationContent content);

  /// Withdraws the notification for [roomId], if one is showing.
  Future<void> cancelRoom(String roomId);
}

/// The operating system's own notifications, through flutter_local_notifications:
///
///  * **Windows** — toast notifications. The app is unpackaged, so the plugin
///    registers [_windowsAppId] under `HKCU\Software\Classes\AppUserModelId`
///    on first use, which is what lets a toast carry the app's name and come
///    back to it when clicked.
///  * **macOS** — the User Notifications framework. macOS asks the user for
///    permission the first time, and the answer lives in System Settings.
///  * **Linux** — `org.freedesktop.Notifications` over the session D-Bus,
///    which every desktop's notification daemon implements. Pure Dart, so the
///    Nix package needs nothing extra for it.
///
/// Anything else (the overlay's engine, a test) gets [isSupported] false and
/// every call is a no-op.
class DesktopNotifications implements NotificationSink {
  DesktopNotifications({required this.onOpen});

  /// Called with the payload of a notification the user clicked.
  final void Function(String? payload) onOpen;

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  /// Fixed so the registry entry and the toast history survive updates.
  static const _windowsAppId = 'Mein1337.Hardline';

  /// The COM class the plugin registers to be activated by a toast click.
  /// Generated once for this app; changing it orphans earlier toasts.
  static const _windowsGuid = 'b7c8e1f3-6a2d-4f5e-9c1b-3d8a7e6f2c41';

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<bool> _init() => _ready ??= () async {
    if (!isSupported) return false;
    try {
      final ok = await _plugin.initialize(
        settings: InitializationSettings(
          windows: const WindowsInitializationSettings(
            appName: kAppName,
            appUserModelId: _windowsAppId,
            guid: _windowsGuid,
          ),
          // Asked on first use rather than at launch: a permission prompt
          // before the user has seen a single message explains nothing.
          macOS: const DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(
            defaultActionName: 'Open',
            defaultIcon: ThemeLinuxIcon('com.mein1337.hardline'),
          ),
        ),
        onDidReceiveNotificationResponse: (response) =>
            onOpen(response.payload),
      );
      return ok ?? false;
    } catch (error, stack) {
      // No notification daemon on the session bus, a refused registration —
      // none of it is worth more than a log line. Chat works without.
      debugPrint('Desktop notifications unavailable: $error\n$stack');
      return false;
    }
  }();

  @override
  Future<void> show(NotificationContent content) async {
    if (!await _init()) return;
    try {
      await _plugin.show(
        id: content.id,
        title: content.title,
        body: content.body,
        payload: content.payload,
        notificationDetails: NotificationDetails(
          macOS: DarwinNotificationDetails(threadIdentifier: content.roomId),
          linux: const LinuxNotificationDetails(
            category: LinuxNotificationCategory.imReceived,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Could not show a notification: $error');
    }
  }

  @override
  Future<void> cancelRoom(String roomId) async {
    if (_ready == null || !await _init()) return;
    try {
      await _plugin.cancel(id: notificationIdForRoom(roomId));
    } catch (error) {
      debugPrint('Could not withdraw a notification: $error');
    }
  }
}
