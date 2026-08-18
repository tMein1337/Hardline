// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:flutter/foundation.dart';

/// Storage key of the account that existed before this feature.
///
/// It maps to the original, unsuffixed database file, so adding multi-account
/// support does not sign anybody out. See `matrix_bootstrap.dart`, which is the
/// only place that turns a key into a filename.
const kDefaultStorageKey = 'default';

/// One remembered account.
///
/// The access token is deliberately **not** here. Each account owns a separate
/// `MatrixSdkDatabase`, and that database already holds the session — so
/// switching is `Client(storageKey).init()`, and this class only has to
/// remember which database belongs to whom and enough to draw a row before that
/// client exists.
///
/// [displayName] and [avatarUrl] are therefore a cache, refreshed whenever an
/// account is active. They may be stale for an account that has not been opened
/// in a while; the row still renders, which is the point.
@immutable
class AccountEntry {
  const AccountEntry({
    required this.storageKey,
    required this.userId,
    this.homeserver = '',
    this.displayName,
    this.avatarUrl,
  });

  /// Opaque, filename-safe, and stable for the life of the account.
  ///
  /// Not the user id: a database has to be created *before* the first login,
  /// when no user id exists yet, and a Matrix id contains characters that have
  /// no business in a path.
  final String storageKey;

  final String userId;

  /// Host only, for display — e.g. `matrix.org`.
  final String homeserver;

  final String? displayName;

  /// An `mxc://` URI, as [MxAvatar] expects.
  final String? avatarUrl;

  /// What to show when the profile has never been fetched.
  String get label => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : localpartOf(userId);

  AccountEntry copyWith({
    String? userId,
    String? homeserver,
    String? displayName,
    String? avatarUrl,
  }) => AccountEntry(
    storageKey: storageKey,
    userId: userId ?? this.userId,
    homeserver: homeserver ?? this.homeserver,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
  );

  Map<String, Object?> toJson() => {
    'storageKey': storageKey,
    'userId': userId,
    'homeserver': homeserver,
    if (displayName != null) 'displayName': displayName,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };

  /// Null for anything unusable, so a corrupt entry drops out of the list
  /// instead of taking the whole registry — and with it the ability to start —
  /// down with it.
  static AccountEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final storageKey = json['storageKey'];
    final userId = json['userId'];
    if (storageKey is! String || storageKey.isEmpty) return null;
    if (userId is! String || userId.isEmpty) return null;

    String? optional(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return AccountEntry(
      storageKey: storageKey,
      userId: userId,
      homeserver: optional('homeserver') ?? '',
      displayName: optional('displayName'),
      avatarUrl: optional('avatarUrl'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountEntry &&
          storageKey == other.storageKey &&
          userId == other.userId &&
          homeserver == other.homeserver &&
          displayName == other.displayName &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode =>
      Object.hash(storageKey, userId, homeserver, displayName, avatarUrl);
}

/// `@alice:example.org` → `alice`. Also used by the user footer.
String localpartOf(String userId) =>
    userId.startsWith('@') ? userId.substring(1).split(':').first : userId;

/// Every account the app knows about, and which one is live.
///
/// Same shape as `AppThemeState` and `VoicePrefsState`: immutable, JSON round
/// trip, and a `fromJson` that degrades rather than throws.
@immutable
class AccountsState {
  const AccountsState({this.entries = const [], this.activeStorageKey});

  const AccountsState.empty() : this();

  final List<AccountEntry> entries;

  /// Null before the first login, and only then.
  final String? activeStorageKey;

  AccountEntry? get active => byKey(activeStorageKey);

  AccountEntry? byKey(String? storageKey) => storageKey == null
      ? null
      : entries.where((e) => e.storageKey == storageKey).firstOrNull;

  AccountEntry? byUserId(String userId) =>
      entries.where((e) => e.userId == userId).firstOrNull;

  bool get isEmpty => entries.isEmpty;

  AccountsState copyWith({
    List<AccountEntry>? entries,
    String? activeStorageKey,
    bool clearActive = false,
  }) => AccountsState(
    entries: entries ?? this.entries,
    activeStorageKey: clearActive
        ? null
        : activeStorageKey ?? this.activeStorageKey,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'entries': [for (final entry in entries) entry.toJson()],
    if (activeStorageKey != null) 'active': activeStorageKey,
  };

  static AccountsState fromJson(Map<String, Object?> json) {
    final raw = json['entries'];
    final entries = raw is List
        ? [for (final item in raw) ?AccountEntry.fromJson(item)]
        : const <AccountEntry>[];

    final active = json['active'];
    final activeKey = active is String && active.isNotEmpty ? active : null;

    return AccountsState(
      entries: entries,
      // An active key naming an account that did not survive parsing would
      // leave the app pointing at a database with no entry to describe it.
      activeStorageKey: entries.any((e) => e.storageKey == activeKey)
          ? activeKey
          : entries.firstOrNull?.storageKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountsState &&
          listEquals(entries, other.entries) &&
          activeStorageKey == other.activeStorageKey;

  @override
  int get hashCode => Object.hash(Object.hashAll(entries), activeStorageKey);
}

/// A fresh, filename-safe storage key.
///
/// Random rather than sequential so that removing an account can never make the
/// next one reuse a directory that a slow teardown has not finished deleting.
String generateStorageKey([Random? random]) {
  final source = random ?? Random.secure();
  final value = source.nextInt(1 << 32).toRadixString(36);
  final salt = source.nextInt(1 << 32).toRadixString(36);
  return '$value$salt';
}
