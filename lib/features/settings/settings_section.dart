import 'package:flutter/material.dart';

/// The panes of the settings screen, in sidebar order.
///
/// The sidebar renders from this enum rather than a hardcoded list, the same
/// way the appearance pane renders from `DiscordSlot.all` — adding a pane is
/// one entry here and one `case` in the content switch, and it cannot be added
/// to one place while being forgotten in the other.
enum SettingsSection {
  account('My Account', Icons.person_outline, group: SettingsGroup.user),
  sessions('Sessions & Security', Icons.devices, group: SettingsGroup.user),
  voice('Voice & Video', Icons.mic_none, group: SettingsGroup.app),
  activity('Activity', Icons.bolt, group: SettingsGroup.app),
  appearance('Appearance', Icons.palette_outlined, group: SettingsGroup.app);

  const SettingsSection(this.label, this.icon, {required this.group});

  final String label;
  final IconData icon;
  final SettingsGroup group;
}

/// Heading a run of sections, as Discord's settings sidebar does.
enum SettingsGroup {
  user('User Settings'),
  app('App Settings');

  const SettingsGroup(this.label);

  final String label;
}
