// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// The panes of the settings screen, in sidebar order.
///
/// The sidebar renders from this enum rather than a hardcoded list, the same
/// way the appearance pane renders from `ColorSlot.all` — adding a pane is
/// one entry here and one `case` in the content switch, and it cannot be added
/// to one place while being forgotten in the other.
enum SettingsSection {
  account('My Account', Icons.person_outline, group: SettingsGroup.user),
  sessions('Sessions', Icons.devices, group: SettingsGroup.user),
  voice('Voice & Video', Icons.mic_none, group: SettingsGroup.app),
  activity('Activity', Icons.bolt, group: SettingsGroup.app),
  appearance('Appearance', Icons.palette_outlined, group: SettingsGroup.app),
  security('Security', Icons.shield_outlined, group: SettingsGroup.app),
  about('About', Icons.info_outline, group: SettingsGroup.about);

  const SettingsSection(this.label, this.icon, {required this.group});

  final String label;
  final IconData icon;
  final SettingsGroup group;
}

/// Heading a run of sections in the settings sidebar.
enum SettingsGroup {
  user('User Settings'),
  app('App Settings'),
  about('Hardline');

  const SettingsGroup(this.label);

  final String label;
}
