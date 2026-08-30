// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import '../../shell/selection_providers.dart';

/// Joins a space by its address.
///
/// The other two ways in are an invitation, which arrives on the rail, and a
/// space you already belong to, which is already there. This is the third:
/// somebody sends you `#gaming:example.org` in a message and you want in.
///
/// Rooms are not joined this way. A room lives inside a space or in the Home
/// list, and the way to one you are not in is the space that contains it —
/// which is what the space overview is for.
class JoinSpaceDialog extends ConsumerStatefulWidget {
  const JoinSpaceDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const JoinSpaceDialog());

  /// Whether [value] could be a room address at all.
  ///
  /// Checked before the request so a typo costs nothing, and deliberately
  /// shallow: `#name:server` and `!id:server` are the two shapes the server
  /// accepts and it can rule on everything else.
  static String? validateAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter the address of a space.';
    if (!trimmed.startsWith('#') && !trimmed.startsWith('!')) {
      return 'An address starts with # — for example #gaming:example.org.';
    }
    if (!trimmed.contains(':')) {
      return 'An address needs a server, after a colon.';
    }
    return null;
  }

  /// The server to ask, taken from the address itself.
  ///
  /// A space on a homeserver we have never spoken to is otherwise unreachable:
  /// the local server has no way to resolve an alias it has never seen unless
  /// it is told where to look.
  static List<String> viaFor(String address) {
    final colon = address.indexOf(':');
    return colon < 0 ? const [] : [address.substring(colon + 1)];
  }

  @override
  ConsumerState<JoinSpaceDialog> createState() => _JoinSpaceDialogState();
}

class _JoinSpaceDialogState extends ConsumerState<JoinSpaceDialog> {
  final _address = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final address = _address.text.trim();
    final problem = JoinSpaceDialog.validateAddress(address);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final client = ref.read(clientProvider);
      final roomId = await client.joinRoom(
        address,
        via: JoinSpaceDialog.viaFor(address),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      // Selecting it rather than leaving somebody to find it on the rail. It
      // has no rooms selected yet, so the space overview is what comes up —
      // which is exactly what somebody who just joined wants to see.
      ref.read(selectedSpaceIdProvider.notifier).select(roomId);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _describe(error);
        });
      }
    }
  }

  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('M_NOT_FOUND') || text.contains('M_UNKNOWN')) {
      return 'Nothing found at that address. Check the spelling, and that the '
          'server after the colon is right.';
    }
    if (text.contains('M_FORBIDDEN')) {
      return 'That space is invite-only. Somebody already in it has to invite '
          'you.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Join a space', style: context.text.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Spaces have addresses like #gaming:example.org. A private '
              'space cannot be joined this way — you have to be invited.',
              style: context.text.subtitle,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _address,
              autofocus: true,
              enabled: !_busy,
              style: context.text.inputText,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: '#gaming:example.org',
              ),
              onSubmitted: (_) => _join(),
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: context.text.subtitle.copyWith(color: colors.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(
          onPressed: _busy ? null : _join,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join'),
        ),
      ],
    );
  }
}
