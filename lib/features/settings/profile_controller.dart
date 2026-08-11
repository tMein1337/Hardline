import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../core/providers/injected_providers.dart';
import '../../core/providers/own_profile_provider.dart';
import '../accounts/account_sync.dart';

/// Writes to the signed-in user's own profile.
///
/// Every path ends by invalidating [ownProfileProvider]. That provider is
/// deliberately not tied to the sync tick — a profile fetch hits the network and
/// recomputing it on every sync would be wasteful — so nothing else would ever
/// notice the change, and the footer would keep showing the old name until the
/// app restarted.
class ProfileController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> setDisplayName(String name) => _run((client) async {
    final userId = client.userID;
    if (userId == null) return;
    await client.setProfileField(userId, 'displayname', {
      'displayname': name.trim(),
    });
  });

  /// Uploads [path] as the avatar.
  ///
  /// Reads the bytes here rather than handing the SDK a path because that is
  /// what `setAvatar` takes — it uploads and then writes the resulting `mxc://`
  /// URI to the profile in one step.
  Future<void> setAvatarFromPath(String path) => _run((client) async {
    final bytes = await File(path).readAsBytes();
    await client.setAvatar(
      MatrixFile(
        bytes: bytes,
        name: p.basename(path),
        mimeType: lookupMimeType(path, headerBytes: bytes),
      ),
    );
  });

  /// `setAvatar(null)` writes an empty string rather than removing the field,
  /// because Synapse does not accept a null there. That is the SDK's problem,
  /// handled inside it.
  Future<void> removeAvatar() => _run((client) => client.setAvatar(null));

  Future<void> _run(Future<void> Function(Client client) action) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    try {
      await action(ref.read(clientProvider));
      ref.invalidate(ownProfileProvider);
      // The account switcher draws rows from the registry's cached copy, which
      // would otherwise keep the old name until this account was next opened.
      ref.invalidate(accountSyncProvider);
      state = const AsyncData(null);
    } catch (error, stack) {
      debugPrint('Profile update failed: $error\n$stack');
      state = AsyncError(error, stack);
    }
  }
}

final profileControllerProvider =
    NotifierProvider<ProfileController, AsyncValue<void>>(
      ProfileController.new,
    );
