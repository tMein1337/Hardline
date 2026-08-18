// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/injected_providers.dart';
import 'account_entry.dart';

const _prefsKey = 'accounts_v1';

/// Reads the registry straight from preferences, without a provider container.
///
/// `main()` needs this: choosing which database to open is the very first
/// decision the app makes, and it happens before `runApp`.
AccountsState readAccounts(SharedPreferences prefs) {
  final raw = prefs.getString(_prefsKey);
  if (raw == null) return const AccountsState.empty();
  try {
    return AccountsState.fromJson(jsonDecode(raw) as Map<String, Object?>);
  } catch (error, stack) {
    // Losing the account list means one re-login, which is survivable.
    // Refusing to start is not.
    debugPrint('Ignoring unreadable account registry: $error\n$stack');
    return const AccountsState.empty();
  }
}

/// Which account to open on launch.
///
/// Falls back to [kDefaultStorageKey] when nothing is registered, which is what
/// adopts the pre-multi-account database: an existing installation has a
/// session in it and finds itself still signed in.
String bootStorageKey(AccountsState accounts) =>
    accounts.activeStorageKey ?? kDefaultStorageKey;

/// Which accounts the app remembers, and which one is live.
///
/// Flat key, not namespaced by user: this *is* the list of users, so keying it
/// by one of them would be circular. It belongs to the machine, like the theme.
///
/// Reads synchronously from the preferences injected in `main()`, because the
/// very first thing the app has to do is decide which database to open — there
/// is no frame to spare for an async read.
class AccountRegistry extends Notifier<AccountsState> {
  @override
  AccountsState build() => readAccounts(ref.watch(prefsProvider));

  /// Adds an account, or refreshes what we cache about an existing one.
  ///
  /// Matched on storage key rather than user id so that re-logging into the
  /// same account through "Add account" replaces the row instead of listing the
  /// person twice — the new session owns a different database, and the old one
  /// is dead the moment its token is gone.
  Future<void> upsert(AccountEntry entry) {
    final existing = state.entries.indexWhere(
      (e) => e.storageKey == entry.storageKey || e.userId == entry.userId,
    );
    final entries = [...state.entries];
    if (existing == -1) {
      entries.add(entry);
    } else {
      entries[existing] = entry;
    }
    return _persist(state.copyWith(entries: entries));
  }

  /// Updates the cached profile of an account already in the list.
  ///
  /// A no-op for an unknown key, so callers can fire this from a profile
  /// listener without first checking whether the account is registered.
  Future<void> refreshProfile(
    String storageKey, {
    String? displayName,
    String? avatarUrl,
  }) {
    final entry = state.byKey(storageKey);
    if (entry == null) return Future.value();

    final next = entry.copyWith(
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
    if (next == entry) return Future.value();

    return _persist(
      state.copyWith(
        entries: [
          for (final e in state.entries) e.storageKey == storageKey ? next : e,
        ],
      ),
    );
  }

  Future<void> remove(String storageKey) {
    final entries = [
      for (final e in state.entries)
        if (e.storageKey != storageKey) e,
    ];
    // Never leave `active` pointing at a removed account: everything downstream
    // reads the active key to decide which database to open.
    final active = state.activeStorageKey == storageKey
        ? entries.firstOrNull?.storageKey
        : state.activeStorageKey;

    return _persist(
      AccountsState(entries: entries, activeStorageKey: active),
    );
  }

  Future<void> setActive(String storageKey) =>
      _persist(state.copyWith(activeStorageKey: storageKey));

  Future<void> _persist(AccountsState next) async {
    state = next;
    await ref.read(prefsProvider).setString(_prefsKey, jsonEncode(next.toJson()));
  }
}

final accountRegistryProvider =
    NotifierProvider<AccountRegistry, AccountsState>(AccountRegistry.new);
