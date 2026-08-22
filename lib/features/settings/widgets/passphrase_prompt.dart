// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';
import '../../auth/widgets/login_text_field.dart';
import '../device_encryption.dart';

/// Asks for a new passphrase, twice.
///
/// Twice because there is no way back from a typo. The passphrase is never
/// written down by the app — that is the point of it — so a mistyped one is
/// indistinguishable from a forgotten one, and the store it locked is gone. The
/// second field is the only check that exists.
///
/// Returns the passphrase, or null if the user backed out.
Future<String?> promptForNewPassphrase(
  BuildContext context, {
  required String title,
  required String action,
  required String explanation,
}) => showDialog<String>(
  context: context,
  builder: (_) => _NewPassphraseDialog(
    title: title,
    action: action,
    explanation: explanation,
  ),
);

class _NewPassphraseDialog extends StatefulWidget {
  const _NewPassphraseDialog({
    required this.title,
    required this.action,
    required this.explanation,
  });

  final String title;
  final String action;
  final String explanation;

  @override
  State<_NewPassphraseDialog> createState() => _NewPassphraseDialogState();
}

class _NewPassphraseDialogState extends State<_NewPassphraseDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final passphrase = _first.text;
    final problem = switch (passphrase) {
      _ when passphrase.length < kMinPassphraseLength =>
        'Use at least $kMinPassphraseLength characters.',
      _ when passphrase != _second.text => 'The two entries do not match.',
      _ => null,
    };

    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.of(context).pop(passphrase);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text(widget.title, style: context.text.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.explanation, style: context.text.subtitle),
            const SizedBox(height: 20),
            LoginTextField(
              label: 'Passphrase',
              controller: _first,
              obscureText: true,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            LoginTextField(
              label: 'Passphrase again',
              controller: _second,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_problem case final problem?) ...[
              const SizedBox(height: 12),
              Text(
                problem,
                style: context.text.subtitle.copyWith(color: colors.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
