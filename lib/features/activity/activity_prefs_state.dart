// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Shortest window the summary will consider "recent".
///
/// Below a minute the list would empty itself faster than anyone can read it,
/// and the 30 second sweep that ages rows out could not keep up anyway.
const Duration kMinRecentWindow = Duration(minutes: 1);

/// Longest window offered, and the horizon the activity log prunes to.
///
/// These are deliberately the same number: the log cannot answer a question
/// about a period it no longer holds, so offering a 48 hour window while
/// storing 24 would silently return half an answer.
const Duration kMaxRecentWindow = Duration(hours: 24);

/// What "recently active" means until somebody changes it.
const Duration kDefaultRecentWindow = Duration(minutes: 30);

/// The windows offered in settings.
///
/// Preset steps rather than a slider: the useful range spans from minutes to a
/// day, and a linear slider over three orders of magnitude spends most of its
/// travel on values nobody wants.
const List<Duration> kRecentWindowChoices = [
  Duration(minutes: 5),
  Duration(minutes: 15),
  kDefaultRecentWindow,
  Duration(hours: 1),
  Duration(hours: 3),
  Duration(hours: 12),
  kMaxRecentWindow,
];

/// Everything the activity summary remembers between runs.
///
/// Mirrors `VoicePrefsState` in shape deliberately: immutable, JSON round-trip,
/// and a `fromJson` that degrades to defaults rather than throwing, so a corrupt
/// preference can never stop the app from starting.
///
/// One blob rather than a controller per concern, for the same reason the voice
/// prefs hold both the device choice and the per-user volumes: they are written
/// together, read together, and belong to the same account.
@immutable
class ActivityPrefsState {
  const ActivityPrefsState({
    this.following = const {},
    this.recentWindow = kDefaultRecentWindow,
    this.showVoice = true,
    this.showActive = true,
    this.showMessages = true,
    this.backfillOnLaunch = false,
  });

  const ActivityPrefsState.empty() : this();

  /// Matrix user ids being followed.
  final Set<String> following;

  /// How far back "recently active" reaches. Clamped on parse; see [fromJson].
  final Duration recentWindow;

  /// Each list can be switched off on its own — someone who only cares who is
  /// in a call should not have to look at a message feed to find out.
  final bool showVoice;
  final bool showActive;
  final bool showMessages;

  /// Whether to ask the server for each room's recent history at start-up.
  ///
  /// Off by default because it costs one `/messages` call per joined room
  /// before the summary is complete. Without it the log starts from the sync
  /// stream plus one seeded event per room, which is thin for the first minutes
  /// after launch — that is the trade, and it is the user's to make.
  final bool backfillOnLaunch;

  bool isFollowing(String userId) => following.contains(userId);

  bool get hasFollowing => following.isNotEmpty;

  ActivityPrefsState copyWith({
    Set<String>? following,
    Duration? recentWindow,
    bool? showVoice,
    bool? showActive,
    bool? showMessages,
    bool? backfillOnLaunch,
  }) => ActivityPrefsState(
    following: following ?? this.following,
    recentWindow: recentWindow ?? this.recentWindow,
    showVoice: showVoice ?? this.showVoice,
    showActive: showActive ?? this.showActive,
    showMessages: showMessages ?? this.showMessages,
    backfillOnLaunch: backfillOnLaunch ?? this.backfillOnLaunch,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    // Sorted so the stored blob is stable: an unordered set would rewrite the
    // preference with different bytes on every save.
    'following': following.toList()..sort(),
    'recentWindowMs': recentWindow.inMilliseconds,
    'showVoice': showVoice,
    'showActive': showActive,
    'showMessages': showMessages,
    'backfillOnLaunch': backfillOnLaunch,
  };

  /// Tolerant of anything: an unknown `version`, wrong types, missing keys.
  ///
  /// The three toggles default to **on** when absent, so a blob written by an
  /// older build does not arrive with every list switched off.
  static ActivityPrefsState fromJson(Map<String, Object?> json) {
    final rawFollowing = json['following'];
    final rawWindow = json['recentWindowMs'];

    bool flag(String key, {required bool orElse}) {
      final value = json[key];
      return value is bool ? value : orElse;
    }

    return ActivityPrefsState(
      following: rawFollowing is List
          ? {
              for (final entry in rawFollowing)
                if (entry is String && entry.isNotEmpty) entry,
            }
          : const {},
      // Clamped at parse time rather than at use, the same argument as
      // `AppThemeState.tooltipDelay`: a hand-edited window of a year would
      // otherwise make "recently active" mean "ever", with nothing on screen
      // to explain why the list never shrinks.
      recentWindow: rawWindow is int
          ? Duration(
              milliseconds: rawWindow.clamp(
                kMinRecentWindow.inMilliseconds,
                kMaxRecentWindow.inMilliseconds,
              ),
            )
          : kDefaultRecentWindow,
      showVoice: flag('showVoice', orElse: true),
      showActive: flag('showActive', orElse: true),
      showMessages: flag('showMessages', orElse: true),
      backfillOnLaunch: flag('backfillOnLaunch', orElse: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityPrefsState &&
          setEquals(following, other.following) &&
          recentWindow == other.recentWindow &&
          showVoice == other.showVoice &&
          showActive == other.showActive &&
          showMessages == other.showMessages &&
          backfillOnLaunch == other.backfillOnLaunch;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(following),
    recentWindow,
    showVoice,
    showActive,
    showMessages,
    backfillOnLaunch,
  );
}
