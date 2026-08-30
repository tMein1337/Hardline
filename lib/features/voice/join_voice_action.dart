// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import '../../theme/theme_context.dart';
import 'call_controller_provider.dart';
import 'voice_joinability.dart';

/// Joins the call in [roomId], asking first when that would change the room.
///
/// Lives here rather than in a widget because the same action is now reachable
/// from more than one place, and the consent step below must not be something a
/// caller can forget to include.
Future<void> joinVoiceCall(
  BuildContext context,
  WidgetRef ref,
  String roomId,
  VoiceJoinability joinability,
) async {
  // Reachable now that the icon is also shown for a call somebody else
  // started. Joining means writing our own call-membership state event, so
  // without the power to send it there is nothing to attempt — and letting the
  // join run anyway produced a failure that read like the call was broken
  // rather than like a permission we do not have.
  if (joinability == VoiceJoinability.forbidden) {
    await _explainForbidden(context);
    return;
  }

  if (joinability == VoiceJoinability.needsEnabling) {
    final confirmed = await _confirmEnable(context);
    if (!confirmed || !context.mounted) return;

    // Explicitly, and before joining: nothing lowers this power level as a side
    // effect, and it is a permanent, room-wide, publicly visible change that
    // this app cannot undo.
    final room = ref.read(clientProvider).getRoomById(roomId);
    if (room == null) return;
    try {
      await enableCallsForEveryone(room);
    } catch (error, stack) {
      debugPrint('[voice] enabling calls failed: $error\n$stack');
      return;
    }
  }

  await ref.read(callControllerProvider).join(roomId);
}

Future<void> _explainForbidden(BuildContext context) async {
  final colors = context.colors;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('You cannot join this call', style: context.text.title),
      content: Text(
        'A call is running here, but this room only lets moderators join '
        'one.\n\n'
        'Somebody who can change the room permissions has to enable calls for '
        'everyone. In this app that happens the first time such a person '
        'joins a call here; in Element it is under the room settings, in '
        'Roles & Permissions.',
        style: context.text.messageBody,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: colors.accent)),
        ),
      ],
    ),
  );
}

Future<bool> _confirmEnable(BuildContext context) async {
  final colors = context.colors;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Enable voice calls?', style: context.text.title),
      content: Text(
        'Voice calls are not enabled in this room yet.\n\n'
        'Joining will change the room permissions so that everyone can '
        'join voice calls. This is visible to all members, and this app '
        'cannot undo it.',
        style: context.text.messageBody,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Enable & Join',
            style: TextStyle(color: colors.voiceConnected),
          ),
        ),
      ],
    ),
  );

  return result ?? false;
}
