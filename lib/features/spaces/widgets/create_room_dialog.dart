// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Visibility` is both a Flutter widget and a Matrix enum, so the SDK is
// prefixed here rather than hiding one name and leaving the next edit to
// rediscover the clash.
import 'package:matrix/matrix.dart' as mx;
import 'package:matrix/matrix.dart' show EventTypes, StateEvent;

import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import '../../settings/widgets/settings_layout.dart';
import '../../shell/selection_providers.dart';
import '../space_hierarchy_provider.dart';
import '../space_summary.dart';

/// What is being made: a room, or a space to put rooms in.
enum CreateKind {
  room('room', 'Create a room', 'Rooms are where conversations happen.'),
  space(
    'space',
    'Create a space',
    'A space is a folder for rooms. It holds no conversation of its own.',
  );

  const CreateKind(this.noun, this.title, this.blurb);

  final String noun;
  final String title;
  final String blurb;
}

/// Makes a room or a space.
///
/// The app had no way to create either. Every room it could show was one
/// somebody had made in Element and invited this account to, which made
/// Hardline unusable as a first client on a new homeserver.
///
/// [parentSpaceId] puts the new room in that space, which is the ordinary case
/// — the control that opens this lives in that space's room list. Null creates
/// a room that belongs to no space, which is where the Home list draws from.
class CreateRoomDialog extends ConsumerStatefulWidget {
  const CreateRoomDialog({super.key, required this.kind, this.parentSpaceId});

  final CreateKind kind;

  /// The space to add the new room to, when there is one.
  final String? parentSpaceId;

  static Future<void> show(
    BuildContext context, {
    required CreateKind kind,
    String? parentSpaceId,
  }) => showDialog(
    context: context,
    builder: (_) => CreateRoomDialog(kind: kind, parentSpaceId: parentSpaceId),
  );

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  final _name = TextEditingController();
  final _topic = TextEditingController();

  /// Private by default, and deliberately.
  ///
  /// A public room is discoverable by anybody on any federated server, and
  /// that is not something to arrive at by leaving a checkbox alone. Somebody
  /// who wants a public room will say so.
  bool _public = false;

  /// Encrypted by default, and also deliberately — with one exception below.
  bool _encrypted = true;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  bool get _isSpace => widget.kind == CreateKind.space;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final client = ref.read(clientProvider);
      final topic = _topic.text.trim();

      final roomId = _isSpace
          ? await client.createSpace(
              name: name,
              topic: topic.isEmpty ? null : topic,
              visibility: _public
                  ? mx.Visibility.public
                  : mx.Visibility.private,
              waitForSync: true,
            )
          : await client.createRoom(
              name: name,
              topic: topic.isEmpty ? null : topic,
              visibility: _public
                  ? mx.Visibility.public
                  : mx.Visibility.private,
              preset: _public
                  ? mx.CreateRoomPreset.publicChat
                  : mx.CreateRoomPreset.privateChat,
              initialState: [
                if (_encrypted)
                  StateEvent(
                    type: EventTypes.Encryption,
                    content: {'algorithm': 'm.megolm.v1.aes-sha2'},
                  ),
                // Calls need `org.matrix.msc3401.call.member` to be sendable
                // by ordinary members. Synapse's default `state_default: 50`
                // means only moderators could join a call in a room made here
                // — the exact situation issue #7.1 was about, arriving fresh
                // in every new room. Set at creation, where it costs nothing
                // and needs nobody's consent, rather than left for the first
                // person who tries to call.
                StateEvent(
                  type: EventTypes.RoomPowerLevels,
                  content: {
                    'events': {'org.matrix.msc3401.call.member': 0},
                  },
                ),
              ],
            );

      // Adding it to the space is a second request, and one that can fail on
      // its own: the room exists either way, so a failure here is reported
      // without pretending the whole thing did not happen.
      final parentId = widget.parentSpaceId;
      if (parentId != null && !_isSpace) {
        final space = client.getRoomById(parentId);
        if (space != null && space.isSpace) {
          await space.setSpaceChild(roomId);
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      _select(roomId, parentId);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _describe(error);
        });
      }
    }
  }

  /// Opens what was just made, so creating something lands you in it.
  void _select(String roomId, String? parentId) {
    if (_isSpace) {
      ref.read(selectedSpaceIdProvider.notifier).select(roomId);
      return;
    }

    final spaceId = parentId ?? kHomeSpaceId;
    if (parentId != null) {
      ref.invalidate(spaceHierarchyProvider(parentId));
    }
    ref
        .read(selectedRoomIdsProvider.notifier)
        .select(spaceId: spaceId, roomId: roomId);
  }

  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('M_FORBIDDEN')) {
      return 'This homeserver does not let this account create '
          '${widget.kind.noun}s.';
    }
    if (text.contains('M_ROOM_IN_USE')) {
      return 'Something with that address already exists here.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text(widget.kind.title, style: context.text.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.kind.blurb, style: context.text.subtitle),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              style: context.text.inputText,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _topic,
              enabled: !_busy,
              style: context.text.inputText,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Topic (optional)'),
            ),
            const SizedBox(height: 8),
            SettingsSwitchTile(
              value: _public,
              title: 'Anyone can find and join',
              subtitle: _public
                  ? 'It will be listed in this homeserver\'s public directory '
                        'and joinable by anybody who finds it.'
                  : 'Only people invited can join. This is the safer default '
                        'and can be changed later.',
              contentPadding: EdgeInsets.zero,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _public = value;
                      // A public room that is also encrypted is a room whose
                      // history nobody joining later can read, which is almost
                      // never what a public room is for — and the combination
                      // is not reversible afterwards.
                      if (value) _encrypted = false;
                    }),
            ),
            if (!_isSpace)
              SettingsSwitchTile(
                value: _encrypted,
                title: 'End-to-end encrypted',
                subtitle: _public
                    ? 'Off for a public room: joining later would show an '
                          'unreadable history, and this cannot be turned off '
                          'again once the room exists.'
                    : 'Cannot be turned off once the room exists.',
                contentPadding: EdgeInsets.zero,
                onChanged: _busy || _public
                    ? null
                    : (value) => setState(() => _encrypted = value),
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
          onPressed: _busy ? null : _create,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
