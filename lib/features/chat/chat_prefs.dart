// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';

/// Not per account: this is about how the composer behaves, not about whose
/// messages are in it.
const _prefsKey = 'chat_prefs_v1';

/// How the chat panel behaves, as distinct from what it contains.
@immutable
class ChatPrefsState {
  const ChatPrefsState({
    this.keepDrafts = true,
    this.notify = true,
    this.notificationPreview = true,
  });

  /// Reads what it can and falls back to the default for the rest.
  ///
  /// Note the direction of the fallback differs from `SecurityPrefsState`,
  /// where an unreadable value resolves to the *careful* answer. Nothing here
  /// is a safety question — the careful answer and the useful answer are the
  /// same one, which is to keep what somebody typed.
  factory ChatPrefsState.fromJson(Map<String, Object?> json) {
    bool read(String key) {
      final value = json[key];
      return value is bool ? value : true;
    }

    return ChatPrefsState(
      keepDrafts: read('keepDrafts'),
      notify: read('notify'),
      notificationPreview: read('notificationPreview'),
    );
  }

  /// Whether unsent message text survives leaving a room and coming back.
  final bool keepDrafts;

  /// Whether new messages raise a desktop notification.
  final bool notify;

  /// Whether that notification shows the text of the message, or only that
  /// there is one.
  final bool notificationPreview;

  ChatPrefsState copyWith({
    bool? keepDrafts,
    bool? notify,
    bool? notificationPreview,
  }) => ChatPrefsState(
    keepDrafts: keepDrafts ?? this.keepDrafts,
    notify: notify ?? this.notify,
    notificationPreview: notificationPreview ?? this.notificationPreview,
  );

  Map<String, Object?> toJson() => {
    'keepDrafts': keepDrafts,
    'notify': notify,
    'notificationPreview': notificationPreview,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPrefsState &&
          keepDrafts == other.keepDrafts &&
          notify == other.notify &&
          notificationPreview == other.notificationPreview;

  @override
  int get hashCode => Object.hash(keepDrafts, notify, notificationPreview);
}

class ChatPrefsController extends Notifier<ChatPrefsState> {
  @override
  ChatPrefsState build() {
    final raw = ref.watch(prefsProvider).getString(_prefsKey);
    if (raw == null) return const ChatPrefsState();
    try {
      return ChatPrefsState.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (error, stack) {
      debugPrint('Ignoring unreadable chat prefs: $error\n$stack');
      return const ChatPrefsState();
    }
  }

  Future<void> setKeepDrafts(bool keep) =>
      _persist(state.copyWith(keepDrafts: keep));

  Future<void> setNotify(bool notify) =>
      _persist(state.copyWith(notify: notify));

  Future<void> setNotificationPreview(bool preview) =>
      _persist(state.copyWith(notificationPreview: preview));

  Future<void> _persist(ChatPrefsState next) async {
    state = next;
    await ref
        .read(prefsProvider)
        .setString(_prefsKey, jsonEncode(next.toJson()));
  }
}

final chatPrefsProvider = NotifierProvider<ChatPrefsController, ChatPrefsState>(
  ChatPrefsController.new,
);
