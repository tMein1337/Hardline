// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// A labelled input: a small tracked-out legend above a filled field, the
/// way a panel labels the control beneath it.
class LoginTextField extends StatelessWidget {
  const LoginTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: context.text.fieldLabel),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          autofocus: autofocus,
          enabled: enabled,
          style: context.text.inputText,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }
}
