import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';
import '../chat/chat_panel.dart';
import '../rooms/room_list_panel.dart';
import '../spaces/space_rail.dart';
import 'widgets/shell_divider.dart';

/// The main three-column layout: space rail, room list, chat.
///
/// Watches nothing sync-related itself — each column subscribes to its own
/// provider, so a change in one cannot repaint the others.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.chatBackground,
      body: const Row(
        children: [
          SpaceRail(),
          ShellDivider(),
          RoomListPanel(),
          ShellDivider(),
          Expanded(child: ChatPanel()),
        ],
      ),
    );
  }
}
