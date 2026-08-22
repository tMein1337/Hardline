// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';

/// Flat, not namespaced by user id.
///
/// The same reasoning as the theme's key. Voice and activity preferences are
/// per account because they hold opinions about *other people* — volumes, mutes,
/// who is followed — and a shared computer must not leak those between logins.
/// This is not that: it answers "how careful should this program be at this
/// keyboard", which does not change when a different account signs in.
const _prefsKey = 'security_prefs_v1';

/// The settings that exist to stop something happening by accident.
@immutable
class SecurityPrefsState {
  const SecurityPrefsState({this.confirmLinks = true});

  factory SecurityPrefsState.fromJson(Map<String, Object?> json) {
    final confirm = json['confirmLinks'];
    return SecurityPrefsState(
      // A missing or unreadable value resolves to the careful answer, never to
      // the permissive one. Turning a safeguard off has to be something
      // somebody chose, not something a corrupt blob did for them.
      confirmLinks: confirm is bool ? confirm : true,
    );
  }

  /// Ask before handing a link from a message to the browser.
  ///
  /// On by default, and deliberately. A link in a chat was written by somebody
  /// else; following it leaves the app, tells that address you were here, and
  /// is one stray click away in a timeline that scrolls under the pointer.
  /// Anyone who finds the step tiresome can say so once and never see it again.
  final bool confirmLinks;

  SecurityPrefsState copyWith({bool? confirmLinks}) =>
      SecurityPrefsState(confirmLinks: confirmLinks ?? this.confirmLinks);

  Map<String, Object?> toJson() => {'confirmLinks': confirmLinks};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityPrefsState && confirmLinks == other.confirmLinks;

  @override
  int get hashCode => confirmLinks.hashCode;
}

/// Owns [SecurityPrefsState] and persists it.
///
/// Structurally a copy of `ThemeController`: read synchronously from the
/// preferences injected in `main()`, set state before the write so the change
/// takes effect immediately, and treat anything unreadable as "use defaults"
/// rather than letting it propagate.
class SecurityPrefsController extends Notifier<SecurityPrefsState> {
  @override
  SecurityPrefsState build() {
    final raw = ref.watch(prefsProvider).getString(_prefsKey);
    if (raw == null) return const SecurityPrefsState();

    try {
      return SecurityPrefsState.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } catch (error, stack) {
      debugPrint('Ignoring unreadable security prefs: $error\n$stack');
      return const SecurityPrefsState();
    }
  }

  Future<void> setConfirmLinks(bool confirm) =>
      _persist(state.copyWith(confirmLinks: confirm));

  Future<void> _persist(SecurityPrefsState next) async {
    state = next;
    await ref
        .read(prefsProvider)
        .setString(_prefsKey, jsonEncode(next.toJson()));
  }
}

final securityPrefsProvider =
    NotifierProvider<SecurityPrefsController, SecurityPrefsState>(
      SecurityPrefsController.new,
    );
