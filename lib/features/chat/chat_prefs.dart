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
  const ChatPrefsState({this.keepDrafts = true});

  /// Reads what it can and falls back to the default for the rest.
  ///
  /// Note the direction of the fallback differs from `SecurityPrefsState`,
  /// where an unreadable value resolves to the *careful* answer. Nothing here
  /// is a safety question — the careful answer and the useful answer are the
  /// same one, which is to keep what somebody typed.
  factory ChatPrefsState.fromJson(Map<String, Object?> json) {
    final keep = json['keepDrafts'];
    return ChatPrefsState(keepDrafts: keep is bool ? keep : true);
  }

  /// Whether unsent message text survives leaving a room and coming back.
  final bool keepDrafts;

  ChatPrefsState copyWith({bool? keepDrafts}) =>
      ChatPrefsState(keepDrafts: keepDrafts ?? this.keepDrafts);

  Map<String, Object?> toJson() => {'keepDrafts': keepDrafts};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPrefsState && keepDrafts == other.keepDrafts;

  @override
  int get hashCode => keepDrafts.hashCode;
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
