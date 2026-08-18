// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';

import '../../../theme/theme_context.dart';
import '../encryption/encryption_setup_dialog.dart';
import '../encryption/encryption_status.dart';
import '../widgets/text_prompt.dart';
import 'sas_display.dart';
import 'verification_session.dart';

/// Drives one verification from either end.
///
/// The same dialog serves an outgoing request and an incoming one; which it is
/// only changes the first screen, because after that the protocol is
/// symmetrical.
class VerificationDialog extends ConsumerStatefulWidget {
  const VerificationDialog({super.key, required this.session});

  final VerificationSession session;

  /// Takes ownership of [session] and disposes it when the dialog closes.
  static Future<void> show(
    BuildContext context,
    VerificationSession session,
  ) async {
    await showDialog<void>(
      context: context,
      // Dismissing by clicking away would silently abandon a verification the
      // other side is still waiting on. Every exit goes through a button that
      // cancels properly.
      barrierDismissible: false,
      builder: (_) => VerificationDialog(session: session),
    );
    await session.cancel();
    session.dispose();
  }

  @override
  ConsumerState<VerificationDialog> createState() =>
      _VerificationDialogState();
}

class _VerificationDialogState extends ConsumerState<VerificationDialog> {
  VerificationSession get _session => widget.session;

  /// Set when the user switches representation for *this* verification.
  ///
  /// Deliberately not written back to the preference: needing to read the other
  /// device's emoji once says nothing about which code is easier to read in
  /// general, and silently rewriting a setting from inside a modal is a poor
  /// way to find out you changed it.
  SasDisplay? _override;

  SasDisplay get _display => resolveSasDisplay(
    _override ?? ref.watch(sasDisplayProvider),
    showsEmoji: _session.showsEmoji,
    showsDigits: _session.showsDigits,
  );

  @override
  void initState() {
    super.initState();
    _session.addListener(_onChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onChanged);
    super.dispose();
  }

  /// Whether the finished verification actually published a signature.
  ///
  /// Resolved once we reach `done`, because it is the difference between a
  /// result that changes what everyone sees and one that only changes what we
  /// see — and the user has no other way to tell them apart.
  bool? _signed;

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_session.state == KeyVerificationState.done && _signed == null) {
      unawaited(_resolveSigned());
    }
  }

  Future<void> _resolveSigned() async {
    final signed = await _session.signedWithAccountKeys();
    if (mounted) setState(() => _signed = signed);
  }

  Future<void> _enterRecoveryKey() async {
    final key = await promptForText(
      context,
      title: 'Recovery key',
      description:
          'Unlocks your account\'s signing keys so this verification is '
          'published, not just remembered here.',
      hint: 'EsT_ …',
      confirmLabel: 'Unlock',
    );
    if (key == null || key.isEmpty) return;
    await _session.unlockSsss(key);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text(_title, style: context.text.title),
      // Wide enough for five emoji tiles per row; seven then wrap 5 + 2 rather
      // than into a ragged three rows.
      content: SizedBox(width: 460, child: _body(context)),
      actions: _actions(context),
    );
  }

  String get _title => switch (_session.state) {
    // Not "Session verified" unconditionally: when nothing was signed, that
    // claim is contradicted by every other client the user owns.
    KeyVerificationState.done =>
      _signed == false ? 'Verified on this device only' : 'Session verified',
    KeyVerificationState.error => 'Verification stopped',
    KeyVerificationState.askSas => 'Do these match?',
    KeyVerificationState.askSSSS => 'Unlock your account keys',
    _ =>
      _session.isSelfVerification
          ? 'Verify your other session'
          : 'Verify ${_session.request.userId}',
  };

  Widget _body(BuildContext context) {
    final colors = context.colors;

    switch (_session.state) {
      case KeyVerificationState.askAccept:
        return Text(
          _session.isSelfVerification
              ? 'Another of your sessions$_deviceSuffix is asking to verify '
                    'this one. Accept only if you started it.'
              : '${_session.request.userId} wants to verify with you.',
          style: context.text.messageBody,
        );

      case KeyVerificationState.askSas:
        return _SasComparison(
          session: _session,
          display: _display,
          // Only offered when the other end agreed to both. Anything else and
          // there is nothing to switch to.
          onSwitch: _session.showsEmoji && _session.showsDigits
              ? () => setState(
                  () => _override = _display == SasDisplay.emoji
                      ? SasDisplay.numbers
                      : SasDisplay.emoji,
                )
              : null,
        );

      case KeyVerificationState.askSSSS:
        return Text(
          'Your account has signing keys, but this session has never held '
          'them. Without them the verification is remembered here and nowhere '
          'else — other clients go on showing the session as unverified.',
          style: context.text.messageBody,
        );

      case KeyVerificationState.done:
        final signed = _signed;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              signed == false ? Icons.gpp_maybe : Icons.verified_user,
              color: signed == false ? colors.warning : colors.success,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                switch (signed) {
                  false =>
                    'Message keys can now be shared, but nothing was signed '
                        'with your account — so Element and every other client '
                        'still show this session as unverified. Fixing that '
                        'takes one step, below.',
                  _ =>
                    _session.isSelfVerification
                        ? 'That session is now verified and signed with your '
                              'account. Every client will see it.'
                        : 'Verified.',
                },
                style: context.text.messageBody,
              ),
            ),
          ],
        );

      case KeyVerificationState.error:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                describeVerificationEnd(_session),
                style: context.text.messageBody,
              ),
            ),
          ],
        );

      case _:
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
                'Waiting for the other session…',
                style: context.text.subtitle,
              ),
            ),
          ],
        );
    }
  }

  String get _deviceSuffix {
    final device = _session.deviceId;
    return device == null ? '' : ' ($device)';
  }

  /// Runs the fix for "nothing was signed", in place.
  ///
  /// Shown on top of this dialog rather than replacing it, so the result line
  /// above re-resolves afterwards and the user watches it change instead of
  /// being told to go and check somewhere else.
  Widget _fixItButton(BuildContext context) {
    // Null while the status is still loading; assume the heavier of the two
    // labels, since offering "set up" on an account that only needs unlocking
    // is a smaller lie than the reverse.
    final needsSetup = ref.watch(encryptionStatusProvider).value?.needsSetup;

    return FilledButton(
      onPressed: () async {
        if (needsSetup ?? true) {
          await EncryptionSetupDialog.show(context);
        } else {
          await unlockWithRecoveryKey(context, ref);
        }
        await _resolveSigned();
      },
      child: Text(
        (needsSetup ?? true) ? 'Set up encryption' : 'Use recovery key',
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final colors = context.colors;

    Widget close(String label) => TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(label, style: TextStyle(color: colors.textMuted)),
    );

    return switch (_session.state) {
      KeyVerificationState.askAccept => [
        TextButton(
          onPressed: () async {
            await _session.reject();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text('Decline', style: TextStyle(color: colors.danger)),
        ),
        FilledButton(onPressed: _session.accept, child: const Text('Accept')),
      ],
      KeyVerificationState.askSas => [
        TextButton(
          onPressed: () async {
            await _session.denyMatch();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(
            "They don't match",
            style: TextStyle(color: colors.danger),
          ),
        ),
        FilledButton(
          onPressed: _session.confirmMatch,
          child: const Text('They match'),
        ),
      ],
      KeyVerificationState.askSSSS => [
        TextButton(
          onPressed: _session.skipSsss,
          child: Text(
            'Continue without it',
            style: TextStyle(color: colors.textMuted),
          ),
        ),
        FilledButton(
          onPressed: _enterRecoveryKey,
          child: const Text('Enter recovery key'),
        ),
      ],
      // A result of "verified here only" is not something to leave the user
      // holding a paragraph of instructions about. The thing that fixes it is
      // one button, so it is one button.
      KeyVerificationState.done => [
        if (_signed == false) _fixItButton(context),
        close('Close'),
      ],
      KeyVerificationState.error => [close('Close')],
      _ => [close('Cancel')],
    };
  }
}

/// Everything the two sides agreed to show, because they may not draw the same
/// one.
///
/// Both representations come from the same shared secret, so comparing either
/// is the whole check — but only if both people are looking at the same kind of
/// thing. Element leads with emoji; two instances of this client will show
/// both, and the digits are the easier of the two to read aloud.
class _SasComparison extends StatelessWidget {
  const _SasComparison({
    required this.session,
    required this.display,
    required this.onSwitch,
  });

  final VerificationSession session;
  final SasDisplay display;

  /// Null when the other end agreed to only one representation.
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final emoji = display == SasDisplay.emoji;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Compare this with the other session. Confirm only if it is '
          'identical.',
          style: context.text.messageBody,
        ),
        const SizedBox(height: 20),
        if (emoji)
          _EmojiRow(emojis: session.emojis)
        else
          _DigitRow(groups: session.digitGroups),
        if (onSwitch case final callback?) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: callback,
              // The escape hatch for the mismatch this whole thing exists to
              // avoid: both codes are agreed and equally valid, but the other
              // client draws only one of them, and it may not be this one.
              child: Text(
                emoji
                    ? 'Other device showing numbers? Switch'
                    : 'Other device showing emoji? Switch',
                style: context.text.subtitle,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The seven emoji, with the names Element prints under them.
class _EmojiRow extends StatelessWidget {
  const _EmojiRow({required this.emojis});

  final List<KeyVerificationEmoji> emojis;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.inputBackground,
        borderRadius: BorderRadius.circular(context.metrics.rowRadius),
        border: Border.all(color: colors.inputBorder),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 12,
        children: [
          for (final emoji in emojis)
            SizedBox(
              width: 68,
              child: Column(
                children: [
                  Text(emoji.emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(height: 4),
                  Text(
                    // The name matters as much as the glyph: emoji render
                    // differently on every platform, and "rabbit" is
                    // comparable where two drawings of a rabbit are not.
                    emoji.name,
                    style: context.text.timestamp,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The twelve digits, in four groups of three.
class _DigitRow extends StatelessWidget {
  const _DigitRow({required this.groups});

  final List<String> groups;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.inputBackground,
            borderRadius: BorderRadius.circular(context.metrics.rowRadius),
            border: Border.all(color: colors.inputBorder),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 8,
            children: [
              for (final group in groups)
                SelectableText(
                  group,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const ['Courier New', 'monospace'],
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: colors.textHeader,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          // Without this line, a client that groups the same digits differently
          // reads as a mismatch — which is the one conclusion that must never be
          // reached by accident.
          'Other clients may show these twelve digits as three groups of four. '
          'The digits are the same, read left to right.',
          style: context.text.timestamp,
        ),
      ],
    );
  }
}
