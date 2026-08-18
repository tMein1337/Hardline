// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import '../widgets/text_prompt.dart';
import 'encryption_setup.dart';
import 'encryption_status.dart';

/// Creates the account's cross-signing identity and hands back the recovery
/// key, once.
///
/// Deliberately not dismissable by tapping outside while it runs: the middle of
/// this flow uploads keys and re-authenticates, and the end of it is the only
/// moment the recovery key exists anywhere it can be read.
class EncryptionSetupDialog extends ConsumerStatefulWidget {
  const EncryptionSetupDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const EncryptionSetupDialog(),
  );

  @override
  ConsumerState<EncryptionSetupDialog> createState() =>
      _EncryptionSetupDialogState();
}

enum _Step { intro, running, showKey, failed }

class _EncryptionSetupDialogState extends ConsumerState<EncryptionSetupDialog> {
  _Step _step = _Step.intro;
  String? _recoveryKey;
  String? _error;
  bool _saved = false;

  Future<void> _start() async {
    setState(() {
      _step = _Step.running;
      _error = null;
    });

    final setup = EncryptionSetup(
      client: ref.read(clientProvider),
      askPassword: () => promptForText(
        context,
        title: 'Confirm it is you',
        description:
            'Your homeserver needs your password before it will accept new '
            'encryption keys.',
        hint: 'Password',
        confirmLabel: 'Confirm',
        obscure: true,
      ),
      askRecoveryKey: () => promptForText(
        context,
        title: 'Existing recovery key',
        description:
            'This account already has secret storage. Enter its recovery key '
            'so it can be reused instead of replaced.',
        hint: 'EsT_ …',
        confirmLabel: 'Unlock',
      ),
    );

    try {
      final key = await setup.createRecovery();
      if (!mounted) return;
      setState(() {
        _recoveryKey = key;
        _step = _Step.showKey;
      });
      ref.invalidate(encryptionStatusProvider);
    } on EncryptionSetupCancelled {
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _step = _Step.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text(_title, style: context.text.title),
      content: SizedBox(width: 460, child: _body(context)),
      actions: _actions(context),
    );
  }

  String get _title => switch (_step) {
    _Step.intro => 'Set up encryption',
    _Step.running => 'Setting up…',
    _Step.showKey => 'Save your recovery key',
    _Step.failed => 'Setup failed',
  };

  Widget _body(BuildContext context) {
    final colors = context.colors;

    switch (_step) {
      case _Step.intro:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This account has no cross-signing identity yet, which is why '
              'other clients show your messages as coming from an unverified '
              'device.',
              style: context.text.messageBody,
            ),
            const SizedBox(height: 12),
            Text(
              'Setting it up creates a signing identity for your account, '
              'signs this session with it, and turns on an encrypted backup of '
              'your message keys. You will get a recovery key to store '
              'somewhere safe.',
              style: context.text.subtitle,
            ),
          ],
        );

      case _Step.running:
        return Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Creating keys and publishing them. This takes a few seconds.',
                style: context.text.subtitle,
              ),
            ),
          ],
        );

      case _Step.showKey:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This is the only time it is shown. It is the only way back into '
              'your encrypted history if you lose every signed-in session.',
              style: context.text.messageBody,
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: colors.inputBackground,
                borderRadius: BorderRadius.circular(context.metrics.rowRadius),
                border: Border.all(color: colors.inputBorder),
              ),
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                _recoveryKey ?? '',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: const ['Courier New', 'monospace'],
                  fontSize: 15,
                  height: 1.5,
                  color: colors.textHeader,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _recoveryKey ?? ''),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recovery key copied')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _saved,
              onChanged: (value) => setState(() => _saved = value ?? false),
              title: Text(
                'I have saved it somewhere safe',
                style: context.text.messageBody,
              ),
            ),
          ],
        );

      case _Step.failed:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error ?? 'Something went wrong.',
                style: context.text.messageBody,
              ),
            ),
          ],
        );
    }
  }

  List<Widget> _actions(BuildContext context) {
    final colors = context.colors;

    return switch (_step) {
      _Step.intro => [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(onPressed: _start, child: const Text('Set up')),
      ],
      _Step.running => const [],
      _Step.showKey => [
        FilledButton(
          // Gated on the checkbox because there is no second chance: the
          // private key it encodes is not stored anywhere we can read again.
          onPressed: _saved ? () => Navigator.of(context).pop() : null,
          child: const Text('Done'),
        ),
      ],
      _Step.failed => [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(onPressed: _start, child: const Text('Try again')),
      ],
    };
  }
}

/// Joins this session to cross-signing that already exists elsewhere.
///
/// Returns true when the session ends up signed.
Future<bool> unlockWithRecoveryKey(BuildContext context, WidgetRef ref) async {
  // Captured before the prompt: everything after it is across an async gap.
  final messenger = ScaffoldMessenger.of(context);

  final key = await promptForText(
    context,
    title: 'Verify with your recovery key',
    description:
        'Unlocks this account\'s encryption keys and signs this session with '
        'them, so other clients stop flagging your messages.',
    hint: 'EsT_ …',
    confirmLabel: 'Verify',
  );
  if (key == null || key.isEmpty) return false;

  final setup = EncryptionSetup(
    client: ref.read(clientProvider),
    // Neither is reachable from `selfSign`; it reads secret storage and signs,
    // touching no endpoint that re-authenticates.
    askPassword: () async => null,
    askRecoveryKey: () async => null,
  );

  try {
    await setup.signInWithRecoveryKey(key);
    ref.invalidate(encryptionStatusProvider);
    messenger.showSnackBar(
      const SnackBar(content: Text('This session is now verified')),
    );
    return true;
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    return false;
  }
}
