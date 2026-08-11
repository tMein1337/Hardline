import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/login_state_provider.dart';
import 'activity_prefs_state.dart';

/// Namespaced by Matrix user id.
///
/// Whom you follow is a statement about *your* account, not about this
/// computer: a shared machine, or simply signing in as someone else, must not
/// inherit another person's follow list. Same argument as the voice prefs.
String _prefsKeyFor(String userId) => 'activity_prefs_v1:$userId';

/// Owns the activity settings and persists them.
///
/// Structurally a copy of `VoicePrefsController`: read synchronously from the
/// preferences injected in `main()`, write after updating state, and treat any
/// unreadable value as "use defaults" rather than letting it propagate.
class ActivityPrefsController extends Notifier<ActivityPrefsState> {
  @override
  ActivityPrefsState build() {
    // loginStateProvider, not clientProvider alone: the user id is null until
    // the session is restored, and without this watch the controller would keep
    // whatever was true before login — namely no user, and so no settings.
    ref.watch(loginStateProvider);

    final userId = ref.watch(clientProvider).userID;
    if (userId == null) return const ActivityPrefsState.empty();

    final raw = ref.watch(prefsProvider).getString(_prefsKeyFor(userId));
    if (raw == null) return const ActivityPrefsState.empty();

    try {
      return ActivityPrefsState.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } catch (error, stack) {
      debugPrint('Ignoring unreadable activity prefs: $error\n$stack');
      return const ActivityPrefsState.empty();
    }
  }

  /// Adds someone to the follow list.
  ///
  /// Following yourself is refused rather than merely discouraged: you would
  /// appear in your own summary, permanently, reporting what you already know.
  Future<void> follow(String userId) {
    if (userId.isEmpty) return Future.value();
    if (userId == ref.read(clientProvider).userID) return Future.value();
    if (state.following.contains(userId)) return Future.value();
    return _persist(
      state.copyWith(following: {...state.following, userId}),
    );
  }

  Future<void> unfollow(String userId) {
    if (!state.following.contains(userId)) return Future.value();
    return _persist(
      state.copyWith(following: {...state.following}..remove(userId)),
    );
  }

  Future<void> toggleFollow(String userId) =>
      state.isFollowing(userId) ? unfollow(userId) : follow(userId);

  Future<void> setRecentWindow(Duration window) => _persist(
    state.copyWith(
      recentWindow: Duration(
        milliseconds: window.inMilliseconds.clamp(
          kMinRecentWindow.inMilliseconds,
          kMaxRecentWindow.inMilliseconds,
        ),
      ),
    ),
  );

  Future<void> setShowVoice(bool show) =>
      _persist(state.copyWith(showVoice: show));

  Future<void> setShowActive(bool show) =>
      _persist(state.copyWith(showActive: show));

  Future<void> setShowMessages(bool show) =>
      _persist(state.copyWith(showMessages: show));

  Future<void> setBackfillOnLaunch(bool enabled) =>
      _persist(state.copyWith(backfillOnLaunch: enabled));

  Future<void> _persist(ActivityPrefsState next) async {
    // State first so the UI follows immediately; the write can lag.
    state = next;

    final userId = ref.read(clientProvider).userID;
    if (userId == null) return;
    await ref
        .read(prefsProvider)
        .setString(_prefsKeyFor(userId), jsonEncode(next.toJson()));
  }
}

final activityPrefsProvider =
    NotifierProvider<ActivityPrefsController, ActivityPrefsState>(
      ActivityPrefsController.new,
    );
