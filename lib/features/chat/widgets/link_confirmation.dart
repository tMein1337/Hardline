// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../settings/security_prefs.dart';

/// Asks before a link leaves the app, and reports whether to go ahead.
///
/// Returns true without showing anything when the user has turned the step off.
/// Callers therefore do not branch on the preference themselves — there is one
/// place that decides, so a second entry point cannot quietly skip it.
///
/// The notifier is read *before* the dialog, not after. The row this was called
/// from can be scrolled out of the tree, or the whole room switched away, while
/// the dialog is open; touching `ref` on a widget that is gone by then throws.
Future<bool> confirmOpenLink(
  BuildContext context,
  WidgetRef ref,
  Uri url,
) async {
  if (!ref.read(securityPrefsProvider).confirmLinks) return true;
  final security = ref.read(securityPrefsProvider.notifier);

  final answer = await showDialog<_LinkAnswer>(
    context: context,
    builder: (_) => _LinkConfirmation(url: url),
  );

  if (answer == null || !answer.open) return false;
  if (answer.stopAsking) await security.setConfirmLinks(false);
  return true;
}

/// What the dialog was closed with.
///
/// "Stop asking" only counts alongside an actual Open. Ticking the box and then
/// cancelling reads as second thoughts about the link, not as a decision to
/// switch a safeguard off for good.
@immutable
class _LinkAnswer {
  const _LinkAnswer({required this.open, required this.stopAsking});

  final bool open;
  final bool stopAsking;
}

class _LinkConfirmation extends StatefulWidget {
  const _LinkConfirmation({required this.url});

  final Uri url;

  @override
  State<_LinkConfirmation> createState() => _LinkConfirmationState();
}

class _LinkConfirmationState extends State<_LinkConfirmation> {
  bool _stopAsking = false;

  void _close({required bool open}) => Navigator.of(
    context,
  ).pop(_LinkAnswer(open: open, stopAsking: _stopAsking));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final host = widget.url.host;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Open this link?', style: context.text.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This leaves Hardline and opens your browser. The site will see '
              'that you followed the link.',
              style: context.text.subtitle,
            ),
            const SizedBox(height: 16),

            // The host on its own line, because it is the part worth reading:
            // it is what decides who is on the other end, and it is the part a
            // long address hides in the middle of itself.
            if (host.isNotEmpty)
              Text(host, style: context.text.username),

            const SizedBox(height: 6),

            // Selectable so a link that looks wrong can be copied out and
            // examined rather than having to be trusted or abandoned.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: colors.inputBackground,
                borderRadius: BorderRadius.circular(context.metrics.rowRadius),
                border: Border.all(color: colors.inputBorder),
              ),
              child: SelectableText(
                widget.url.toString(),
                style: context.text.timestamp.copyWith(
                  color: colors.textPrimary,
                ),
                maxLines: 4,
              ),
            ),
            const SizedBox(height: 8),

            CheckboxListTile(
              value: _stopAsking,
              onChanged: (value) =>
                  setState(() => _stopAsking = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(
                "Don't ask again",
                style: context.text.messageBody,
              ),
              subtitle: Text(
                'Links will open straight away. Settings → Security turns this '
                'back on.',
                style: context.text.timestamp,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _close(open: false),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(
          onPressed: () => _close(open: true),
          child: const Text('Open link'),
        ),
      ],
    );
  }
}
