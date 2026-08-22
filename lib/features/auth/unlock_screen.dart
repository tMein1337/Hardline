// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../app.dart';
import '../../bootstrap/matrix_bootstrap.dart';
import '../../core/providers/injected_providers.dart';
import '../../core/storage/store_cipher.dart';
import '../../theme/theme_context.dart';
import '../../theme/theme_controller.dart';
import '../accounts/account_entry.dart';
import '../accounts/account_registry.dart';
import 'widgets/login_card.dart';
import 'widgets/login_text_field.dart';

/// How the launch got past the lock.
@immutable
class UnlockOutcome {
  const UnlockOutcome.unlocked(String this.passphrase) : erased = false;
  const UnlockOutcome.erased() : passphrase = null, erased = true;

  /// The passphrase that opened the store, held for the rest of the session.
  final String? passphrase;

  /// The stores were deleted rather than opened, because the passphrase was
  /// gone. Everything after this point is a first launch.
  final bool erased;
}

/// Blocks the launch until the encrypted store is open, or gone.
///
/// This runs a whole app of its own, before the real one. It has to: the
/// passphrase is what opens the database, and the database is what `main()`
/// builds the client from, so there is no client — and therefore no shell, no
/// router, no timeline — to show this inside. `runApp` is called twice, and the
/// second call replaces this tree with the real one.
///
/// It gets the theme for free by being a `ProviderScope` over the same
/// preferences the real app will use, so the lock screen is already in the
/// user's colours rather than in Material defaults.
Future<UnlockOutcome> runUnlockGate({
  required SharedPreferences prefs,
  required String storageKey,
}) {
  // The gate opens a database before `buildMatrixClient` gets the chance to,
  // so the FFI registration cannot be left to it.
  sqfliteFfiInit();

  final outcome = Completer<UnlockOutcome>();
  runApp(
    unlockRoot(
      prefs: prefs,
      storageKey: storageKey,
      // The screen disables its buttons while it is working, so a second answer
      // should not be reachable — but this tree keeps running until `runApp`
      // replaces it, and completing a `Completer` twice throws from somewhere
      // with no context at all. Cheaper to be sure.
      onDone: (result) {
        if (!outcome.isCompleted) outcome.complete(result);
      },
    ),
  );
  return outcome.future;
}

/// The lock screen's root, carrying [kUnlockScopeKey].
///
/// That key is load-bearing rather than decorative: without it the app's root
/// scope would be reconciled into this one instead of replacing it, and
/// Riverpod would abort the launch over the change in override count. See
/// [kUnlockScopeKey] for the whole of it.
@visibleForTesting
Widget unlockRoot({
  required SharedPreferences prefs,
  required String storageKey,
  required ValueChanged<UnlockOutcome> onDone,
}) => ProviderScope(
  key: kUnlockScopeKey,
  overrides: [prefsProvider.overrideWithValue(prefs)],
  child: _UnlockApp(storageKey: storageKey, onDone: onDone),
);

class _UnlockApp extends ConsumerWidget {
  const _UnlockApp({required this.storageKey, required this.onDone});

  final String storageKey;
  final ValueChanged<UnlockOutcome> onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Hardline',
      debugShowCheckedModeBanner: false,
      theme: ref.watch(themeDataProvider),
      home: UnlockScreen(storageKey: storageKey, onDone: onDone),
    );
  }
}

/// Asks for the passphrase that opens this device's stores.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({
    super.key,
    required this.storageKey,
    required this.onDone,
  });

  /// The account whose store is used to check the passphrase. All of this
  /// device's stores share one, so opening any of them proves it.
  final String storageKey;

  final ValueChanged<UnlockOutcome> onDone;

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final passphrase = _passphrase.text;
    if (passphrase.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Opened only to be sure it opens, then closed again — `buildMatrixClient`
      // does the real one moments later. Checking here rather than there is what
      // lets a wrong passphrase be a message on this screen instead of a crash
      // during launch.
      final probe = await openStore(
        path: await accountStorePath(widget.storageKey),
        passphrase: passphrase,
      );
      await probe.close();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is WrongStorePassphrase
            ? 'That passphrase does not open this device’s data.'
            : '$error';
      });
      return;
    }

    widget.onDone(UnlockOutcome.unlocked(passphrase));
  }

  /// Deletes every store on this device, then lets the launch continue.
  ///
  /// The only way out of a forgotten passphrase, and it is not a recovery —
  /// there is nothing to recover with. Signing in again gets the account back
  /// from the homeserver; it does not get back the Megolm keys that were in the
  /// store, so history in encrypted rooms that no other device holds keys for
  /// is gone for good. The dialog says so in those words.
  Future<void> _erase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _EraseConfirmation(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    final prefs = ref.read(prefsProvider);
    final keys = <String>{
      kDefaultStorageKey,
      ...readAccounts(prefs).entries.map((e) => e.storageKey),
    };
    for (final key in keys) {
      await deleteAccountStorage(key);
    }
    await forgetAllAccounts(prefs);

    widget.onDone(const UnlockOutcome.erased());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.timelineBackground,
      body: LoginCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 32, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Hardline is locked',
              textAlign: TextAlign.center,
              style: context.text.title.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'This device’s messages, keys and attachments are encrypted. '
              'The passphrase is not stored anywhere, so it has to be typed.',
              textAlign: TextAlign.center,
              style: context.text.subtitle,
            ),
            const SizedBox(height: 24),

            if (_error != null) ...[
              _UnlockError(message: _error!),
              const SizedBox(height: 16),
            ],

            LoginTextField(
              label: 'Passphrase',
              controller: _passphrase,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colors.textOnAccent,
                      ),
                    )
                  : const Text('Unlock'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _erase,
              child: Text(
                'I have lost the passphrase',
                style: TextStyle(color: colors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EraseConfirmation extends StatelessWidget {
  const _EraseConfirmation();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Erase this device’s data?', style: context.text.title),
      content: SizedBox(
        width: 420,
        child: Text(
          'There is no way to recover an encrypted store without its '
          'passphrase, so the only way past this screen is to delete it.\n\n'
          'Every account signed in here is removed from this device, and you '
          'can sign in again afterwards. What does not come back are the '
          'encryption keys stored here: messages in encrypted rooms that no '
          'other device of yours holds keys for will stay unreadable, on this '
          'machine and on any device you sign in on later.\n\n'
          'Your account and your messages on the homeserver are untouched.',
          style: context.text.subtitle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Erase and start over'),
        ),
      ],
    );
  }
}

class _UnlockError extends StatelessWidget {
  const _UnlockError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.metrics.rowRadius),
        border: Border.all(color: colors.danger.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: context.text.subtitle.copyWith(color: colors.danger),
      ),
    );
  }
}
