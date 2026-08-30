// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';

/// Invites somebody to a room or a space, by user id.
///
/// By id rather than by search, and that is a real limitation rather than a
/// simplification: the user directory would let somebody be found by name, but
/// it is a per-homeserver feature that many deployments disable, and a search
/// box that silently returns nothing on half of them is worse than a field
/// that says what it wants.
///
/// Several at once, because inviting a group to a new space one dialog at a
/// time is the kind of thing that makes people give up and use Element.
class InvitePeopleDialog extends ConsumerStatefulWidget {
  const InvitePeopleDialog({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.isSpace,
  });

  final String roomId;
  final String roomName;
  final bool isSpace;

  static Future<void> show(
    BuildContext context, {
    required String roomId,
    required String roomName,
    required bool isSpace,
  }) => showDialog(
    context: context,
    builder: (_) => InvitePeopleDialog(
      roomId: roomId,
      roomName: roomName,
      isSpace: isSpace,
    ),
  );

  /// Whether [value] is shaped like a user id.
  ///
  /// Shallow on purpose. `@name:server` is the shape; whether that person
  /// exists is the homeserver's to answer, and it is the only thing that can.
  static String? validateUserId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter a user ID.';
    if (!trimmed.startsWith('@')) {
      return 'A user ID starts with @ — for example @alice:example.org.';
    }
    if (!trimmed.contains(':')) {
      return 'A user ID needs a server, after a colon.';
    }
    return null;
  }

  @override
  ConsumerState<InvitePeopleDialog> createState() => _InvitePeopleDialogState();
}

class _InvitePeopleDialogState extends ConsumerState<InvitePeopleDialog> {
  final _input = TextEditingController();

  /// Everybody invited in this sitting, and how it went. Null means it worked.
  ///
  /// Kept rather than replaced so inviting five people leaves five lines
  /// saying what happened to each, instead of only the last one.
  final _results = <String, String?>{};

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final userId = _input.text.trim();
    final problem = InvitePeopleDialog.validateUserId(userId);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    String? failure;
    try {
      final room = ref.read(clientProvider).getRoomById(widget.roomId);
      if (room == null) throw StateError('That room is no longer here.');
      await room.invite(userId);
    } catch (error) {
      failure = _describe(error);
    }

    if (!mounted) return;
    setState(() {
      _results[userId] = failure;
      _busy = false;
      _input.clear();
    });
  }

  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('M_FORBIDDEN')) {
      return 'not allowed — you may not have permission to invite here';
    }
    if (text.contains('not a valid user')) {
      return 'no such user on that server';
    }
    if (text.contains('already in the room') || text.contains('M_BAD_STATE')) {
      return 'already here, or already invited';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final noun = widget.isSpace ? 'space' : 'room';

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Invite to ${widget.roomName}', style: context.text.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isSpace
                  ? 'They will be able to see this space, and the rooms in it '
                        'that they are allowed to see. Rooms inside it are '
                        'invited to separately.'
                  : 'They will be able to read this room from the point they '
                        'join.',
              style: context.text.subtitle,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              autofocus: true,
              enabled: !_busy,
              style: context.text.inputText,
              decoration: InputDecoration(
                labelText: 'User ID',
                hintText: '@alice:example.org',
                suffixIcon: IconButton(
                  tooltip: 'Invite to this $noun',
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  onPressed: _busy ? null : _invite,
                ),
              ),
              onSubmitted: (_) => _invite(),
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: context.text.timestamp.copyWith(color: colors.danger),
              ),
            ],
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final entry in _results.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        entry.value == null
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 14,
                        color: entry.value == null
                            ? colors.success
                            : colors.danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.value == null
                              ? '${entry.key} — invited'
                              : '${entry.key} — ${entry.value}',
                          style: context.text.timestamp,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Done', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }
}
