// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/room_capabilities.dart';
import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../../rooms/room_admin.dart';
import '../../shell/selection_providers.dart';
import '../space_hierarchy_provider.dart';
import '../space_list_provider.dart';
import 'invite_people_dialog.dart';

/// What a space contains, and a way into it.
///
/// Shown when a space is selected and no room in it is. Before this the same
/// position drew "No room selected", and a space whose rooms you had not
/// joined drew "This space has no rooms you have joined" — a dead end with
/// nothing to click, in a client that had no way to join a room at all.
class SpaceHome extends ConsumerWidget {
  const SpaceHome({super.key, required this.spaceId});

  static const _maxContentWidth = 720.0;

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(spaceHierarchyProvider(spaceId));
    final name = ref
        .watch(spaceListProvider)
        .items
        .where((space) => space.id == spaceId)
        .map((space) => space.name)
        .firstOrNull;

    return Container(
      color: context.colors.timelineBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: children.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _Message(
              text:
                  'Could not read what is in this space.\n\n$error\n\n'
                  'The rooms you have already joined are still in the list on '
                  'the left.',
            ),
            data: (contents) => contents.children.isEmpty
                ? const _Message(
                    text:
                        'This space is empty, or its contents are not visible '
                        'to you. Somebody who can add rooms to it has to do so '
                        'before there is anything here.',
                  )
                : _List(
                    spaceId: spaceId,
                    spaceName: name,
                    rooms: contents.children,
                    truncated: contents.truncated,
                  ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Text(
      text,
      style: context.text.subtitle,
      textAlign: TextAlign.center,
    ),
  );
}

class _List extends ConsumerWidget {
  const _List({
    required this.spaceId,
    required this.spaceName,
    required this.rooms,
    required this.truncated,
  });

  final String spaceId;
  final String? spaceName;
  final List<SpaceChild> rooms;

  /// Whether the server had more than was fetched.
  final bool truncated;

  /// "3 rooms and 2 spaces in here."
  ///
  /// Counted apart, because a space listed inside another is a place with
  /// contents of its own and calling it a room undersells what is behind it.
  String get _summary {
    final spaces = rooms.where((room) => room.isSpace).length;
    final plain = rooms.length - spaces;
    final parts = [
      if (plain > 0) '$plain ${plain == 1 ? "room" : "rooms"}',
      if (spaces > 0) '$spaces ${spaces == 1 ? "space" : "spaces"}',
    ];
    // Not "all of it" when it is not: a list that stops without a word reads
    // as the whole list.
    return '${truncated ? "The first " : ""}${parts.join(" and ")} in here.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(clientProvider).getRoomById(spaceId);
    final removable = space != null && canRemoveFromSpace(space);

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spaceName ?? 'Space', style: context.text.title),
                  const SizedBox(height: 4),
                  Text(_summary, style: context.text.subtitle),
                ],
              ),
            ),
            // Only when the server would accept it. An invite button that
            // fails on the click is worse than no invite button, because the
            // failure looks like the app being broken rather than like a
            // permission somebody does not have.
            if (space != null && canInvite(space))
              OutlinedButton.icon(
                onPressed: () => InvitePeopleDialog.show(
                  context,
                  roomId: spaceId,
                  roomName: spaceName ?? 'this space',
                  isSpace: true,
                ),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Invite'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        for (final room in rooms) ...[
          _Row(
            key: ValueKey(room.roomId),
            spaceId: spaceId,
            room: room,
            removable: removable,
          ),
          const SizedBox(height: 8),
        ],
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This space has more in it than is listed here. Reading it '
              'stops after $kMaxHierarchyRooms entries; the rest can be '
              'joined by address.',
              style: context.text.timestamp,
            ),
          ),
      ],
    );
  }
}

class _Row extends ConsumerStatefulWidget {
  const _Row({
    super.key,
    required this.spaceId,
    required this.room,
    required this.removable,
  });

  final String spaceId;
  final SpaceChild room;

  /// Whether this account may take rooms out of this space.
  final bool removable;

  @override
  ConsumerState<_Row> createState() => _RowState();
}

class _RowState extends ConsumerState<_Row> {
  bool _joining = false;
  String? _error;

  /// Takes the room out of the space, and nothing else.
  ///
  /// Asked first, in words that say what it is not. "Remove" beside a room
  /// reads as "delete the room" to anybody who has not thought about what a
  /// space is, and the two could not be further apart: this leaves the room,
  /// its members and its history exactly as they were.
  Future<void> _remove() async {
    final colors = context.colors;
    final noun = widget.room.isSpace ? 'space' : 'room';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.floatingSurface,
        title: Text(
          'Take ${widget.room.name} out of this space?',
          style: context.text.title,
        ),
        content: SizedBox(
          width: 400,
          child: Text(
            'The $noun itself is not touched: everybody stays in it and '
            'nothing in it is deleted. It just stops being listed here, for '
            'everyone who can see this space.',
            style: context.text.messageBody,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Take out', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await ref
          .read(roomAdminProvider)
          .removeFromSpace(widget.spaceId, widget.room.roomId);
      // The overview is a fetch, not a view of local state, so it has to be
      // told. The room list finds out from sync on its own.
      ref.invalidate(spaceHierarchyProvider(widget.spaceId));
      if (mounted) setState(() => _joining = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = error.toString().contains('M_FORBIDDEN')
              ? 'The homeserver refused — you may not have permission to '
                    'change what this space lists.'
              : error.toString();
        });
      }
    }
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      final client = ref.read(clientProvider);
      // By id rather than by alias, and with the space itself as a via: a room
      // this account has never touched may live on a server we have never
      // spoken to, and the space is the only thing that knows where it is.
      await client.joinRoom(widget.room.roomId, via: _viaServers());

      if (!mounted) return;
      // The hierarchy carries a joined flag that is now stale, and the room
      // list is driven by sync rather than by this — so only the former needs
      // telling.
      ref.invalidate(spaceHierarchyProvider(widget.spaceId));
      if (widget.room.isSpace) {
        _openSpace();
      } else {
        _open();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  /// Servers worth trying, newest knowledge first.
  ///
  /// The space's own server always knows about its children, and for a room
  /// nobody here has joined it is frequently the only one that does.
  List<String> _viaServers() {
    final colon = widget.spaceId.indexOf(':');
    if (colon < 0) return const [];
    return [widget.spaceId.substring(colon + 1)];
  }

  void _open() {
    ref
        .read(selectedRoomIdsProvider.notifier)
        .select(spaceId: widget.spaceId, roomId: widget.room.roomId);
  }

  /// A space opens *as* a space — it becomes the rail selection rather than
  /// the open room inside its parent.
  void _openSpace() =>
      ref.read(selectedSpaceIdProvider.notifier).select(widget.room.roomId);

  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('M_FORBIDDEN')) {
      return 'This room is invite-only. Somebody already in it has to invite '
          'you.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final room = widget.room;

    return Hoverable(
      cursor: room.joined ? SystemMouseCursors.click : MouseCursor.defer,
      onTap: room.joined ? _open : null,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hovered && room.joined
              ? colors.listItemHover
              : colors.elevatedSurface,
          borderRadius: BorderRadius.circular(context.metrics.rowRadius * 3),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MxAvatar(
                  name: room.name,
                  seed: room.roomId,
                  mxcUri: room.avatarMxc,
                  size: 34,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              room.name,
                              style: context.text.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (room.isEncrypted) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.lock, size: 12, color: colors.textFaint),
                          ],
                          if (room.isSpace) ...[
                            const SizedBox(width: 6),
                            Text('space', style: context.text.timestamp),
                          ],
                        ],
                      ),
                      Text(
                        '${room.memberCount} '
                        '${room.memberCount == 1 ? "member" : "members"}',
                        style: context.text.timestamp,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _action(context),
                // Only when the server would accept it, like the invite
                // button above. It is a change to the space, so being able
                // to do anything in the room listed is beside the point.
                if (widget.removable && !_joining)
                  IconButton(
                    key: Key('space_remove_${room.roomId}'),
                    tooltip: 'Take out of this space',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.link_off, color: colors.textFaint),
                    onPressed: _remove,
                  ),
              ],
            ),
            if (room.topic case final topic? when topic.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                topic,
                style: context.text.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_error case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: context.text.timestamp.copyWith(color: colors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context) {
    if (_joining) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (widget.room.joined) {
      return widget.room.isSpace
          ? TextButton(onPressed: _openSpace, child: const Text('Open'))
          : TextButton(onPressed: _open, child: const Text('Open'));
    }

    // A nested space can be joined now that the rail has somewhere to put it
    // and something to do with it. It used to say "Not joined" and offer
    // nothing, on the grounds that a second rail entry would be a surprise —
    // but that was really the absence of any way to join a space at all, and
    // arriving on the rail is exactly what joining one means.
    return FilledButton(
      onPressed: _join,
      child: Text(widget.room.isSpace ? 'Join space' : 'Join'),
    );
  }
}
