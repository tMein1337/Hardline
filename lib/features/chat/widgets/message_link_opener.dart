// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../core/util/open_link.dart';
import '../../activity/activity_navigation.dart';
import '../message_links.dart';
import 'link_confirmation.dart';

/// Opens a link somebody put in a message.
///
/// A permalink that resolves to a room in this app never leaves it, so there
/// is nothing to confirm. Everything else goes through the confirmation step,
/// which shows the real address — the one place that decides, for plain-text
/// links and formatted ones alike.
Future<void> openMessageLink(
  BuildContext context,
  WidgetRef ref,
  Uri target,
) async {
  final matrixTo = parseMatrixTo(target);
  if (matrixTo != null && _openHere(ref, matrixTo)) return;

  if (!await confirmOpenLink(context, ref, target)) return;
  if (!context.mounted) return;
  await openExternalUrl(context, target);
}

/// Opens a `matrix.to` link inside the app, and reports whether it could.
///
/// A permalink to a room this account is already in has no business going out
/// to a web page that exists only to send the reader back again. A room we are
/// *not* in, or a link to a person, is a different matter: matrix.to's page
/// offers to join or to start a chat, which is more than this app has to show
/// for one, so those are left to the browser.
bool _openHere(WidgetRef ref, MatrixToTarget target) {
  final identifier = target.identifier;
  final client = ref.read(clientProvider);
  final room = identifier.startsWith('#')
      ? client.getRoomByAlias(identifier)
      : client.getRoomById(identifier);
  if (room == null) return false;

  final eventId = target.eventId;
  if (eventId == null) {
    openRoom(ref, room.id);
  } else {
    jumpToMessage(ref, room.id, eventId);
  }
  return true;
}
