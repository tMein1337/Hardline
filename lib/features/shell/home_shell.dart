// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';
import '../chat/chat_panel.dart';
import '../rooms/room_list_panel.dart';
import '../settings/verification/incoming_verification.dart';
import '../spaces/space_rail.dart';
import 'widgets/background_workers.dart';
import 'widgets/shell_divider.dart';

/// The main three-column layout: space rail, room list, chat.
///
/// Watches nothing sync-related itself — each column subscribes to its own
/// provider, so a change in one cannot repaint the others.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    // Wraps the whole shell so a verification started on another device is
    // answerable from any screen, not only from the settings pane that lists
    // sessions.
    return IncomingVerificationListener(
      child: Scaffold(
        backgroundColor: context.colors.timelineBackground,
        body: const Row(
          children: [
            // Zero-sized. Starts the activity log so it collects from the first
            // sync rather than from the first time somebody opens the Home
            // screen, and drives the sweep that clears badges left behind by
            // calls that have ended.
            BackgroundWorkers(),
            SpaceRail(),
            ShellDivider(),
            RoomListPanel(),
            ShellDivider(),
            Expanded(child: ChatPanel()),
          ],
        ),
      ),
    );
  }
}
