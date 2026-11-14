// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../../rooms/room_members.dart';

/// Invites somebody to a room or a space, by user id.
///
/// By id rather than by search, and that is a real limitation rather than a
/// simplification: the user directory would let somebody be found by name, but
/// it is a per-homeserver feature that many deployments disable, and a search
/// box that silently returns nothing on half of them is worse than a field
/// that says what it wants.
///
/// What it can do without a directory is complete from people this account
/// is already in a room with — see `invitableMatching`. Their ids are in local
/// state, so typing part of a name offers them and no request is made.
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
      // What was typed is not an id. If it names exactly one person this
      // account already knows, that is plainly who was meant — pressing Enter
      // on "ali" with one Alice on offer should not be answered with a
      // lecture about what a user id starts with.
      final known = _suggestions();
      if (known.length == 1) return _inviteId(known.single.userId);
      setState(() => _error = problem);
      return;
    }
    await _inviteId(userId);
  }

  /// People already known to this account whom the text could mean.
  List<KnownPerson> _suggestions() => invitableMatching(
    ref.read(clientProvider),
    roomId: widget.roomId,
    query: _input.text,
  );

  Future<void> _inviteId(String userId) async {
    if (_busy) return;
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
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _invite(),
            ),
            // Offered, never required: the field still takes any id. These
            // are only the people whose id is already sitting in a room this
            // account shares with them — which is nearly everybody anybody
            // wants to invite, and needs no directory to find.
            for (final person in _suggestions())
              Hoverable(
                onTap: _busy ? null : () => _inviteId(person.userId),
                builder: (context, hovered) => Container(
                  key: Key('invite_suggestion_${person.userId}'),
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: hovered ? colors.listItemHover : null,
                    borderRadius: BorderRadius.circular(
                      context.metrics.rowRadius,
                    ),
                  ),
                  child: Row(
                    children: [
                      MxAvatar(
                        name: person.name,
                        seed: person.userId,
                        mxcUri: person.avatarMxc,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          person.name,
                          style: context.text.subtitle.copyWith(
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // The id beside the name, because two people can share
                      // a name and this is an invitation going to one of them.
                      Flexible(
                        child: Text(
                          person.userId,
                          style: context.text.timestamp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
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
