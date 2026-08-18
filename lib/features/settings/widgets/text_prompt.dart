// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// A one-field dialog. Returns the trimmed text, or null if cancelled.
///
/// The controller lives inside a [StatefulWidget] rather than beside the
/// `showDialog` call, because the returned future completes when the route is
/// popped while the field is still mounted for the exit animation — disposing
/// the controller there throws "used after being disposed" at the user.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? description,
  String? hint,
  String initial = '',
  String confirmLabel = 'Save',
  bool obscure = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPrompt(
    title: title,
    description: description,
    hint: hint,
    initial: initial,
    confirmLabel: confirmLabel,
    obscure: obscure,
  ),
);

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.description,
    required this.hint,
    required this.initial,
    required this.confirmLabel,
    required this.obscure,
  });

  final String title;
  final String? description;
  final String? hint;
  final String initial;
  final String confirmLabel;
  final bool obscure;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text(widget.title, style: context.text.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.description case final text?) ...[
              Text(text, style: context.text.subtitle),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: widget.obscure,
              style: context.text.inputText,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: context.text.subtitle,
                filled: true,
                fillColor: colors.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    context.metrics.rowRadius,
                  ),
                  borderSide: BorderSide(color: colors.inputBorder),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
