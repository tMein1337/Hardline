import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../accounts/account_actions.dart';
import '../shell/widgets/shell_divider.dart';
import 'panes/account_pane.dart';
import 'panes/appearance_pane.dart';
import 'panes/sessions_pane.dart';
import 'panes/voice_pane.dart';
import 'settings_section.dart';

/// The full-screen settings surface.
///
/// A route rather than a dialog: the sessions list and the appearance grid both
/// want the whole window, and Discord — which this app's layout follows —
/// settles for nothing less. It sits above the shell, so the call keeps running
/// and the sync keeps arriving underneath.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.initialSection});

  final SettingsSection? initialSection;

  static Future<void> open(
    BuildContext context, {
    SettingsSection? section,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        // Opaque: nothing of the shell should show through, and an opaque route
        // lets Flutter stop painting what is behind it.
        opaque: true,
        transitionDuration: const Duration(milliseconds: 140),
        reverseTransitionDuration: const Duration(milliseconds: 100),
        pageBuilder: (_, _, _) => SettingsScreen(initialSection: section),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 1.04, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late SettingsSection _section = widget.initialSection ?? SettingsSection.account;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CallbackShortcuts(
      // Nothing inside wants Esc for itself — the pickers and prompts are
      // dialogs, which take the key first because they are the focused route.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.chatBackground,
          body: Row(
            children: [
              _Sidebar(
                selected: _section,
                onSelect: (section) => setState(() => _section = section),
              ),
              const ShellDivider(),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _paneFor(_section)),
                    Positioned(top: 20, right: 20, child: const _CloseButton()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paneFor(SettingsSection section) => switch (section) {
    SettingsSection.account => const AccountPane(),
    SettingsSection.sessions => const SessionsPane(),
    SettingsSection.voice => const VoicePane(),
    SettingsSection.appearance => const AppearancePane(),
  };
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 232,
      color: colors.channelSidebar,
      padding: const EdgeInsets.only(top: 60, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final group in SettingsGroup.values) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: Text(
                      group.label.toUpperCase(),
                      style: context.text.sectionHeader,
                    ),
                  ),
                  for (final section in SettingsSection.values)
                    if (section.group == group)
                      _SidebarItem(
                        section: section,
                        selected: section == selected,
                        onTap: () => onSelect(section),
                      ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          Divider(color: colors.divider, height: 17),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: _SignOutItem(),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(context.metrics.rowRadius);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? colors.listItemSelected : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: colors.listItemHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 18,
                  color: selected ? colors.textHeader : colors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.label,
                    style: selected
                        ? context.text.channelNameActive
                        : context.text.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Signing out closes settings on its own, because the router replaces
/// everything below this route the moment the session goes.
class _SignOutItem extends ConsumerWidget {
  const _SignOutItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final radius = BorderRadius.circular(context.metrics.rowRadius);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        hoverColor: colors.danger.withValues(alpha: 0.12),
        onTap: () async {
          final confirmed = await confirmSignOut(context);
          if (!confirmed || !context.mounted) return;
          Navigator.of(context).pop();
          await ref.read(accountActionsProvider.notifier).signOutActive();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: colors.danger),
              const SizedBox(width: 10),
              Text(
                'Log Out',
                style: context.text.channelName.copyWith(color: colors.danger),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared by the sidebar and the account pane, so the warning is worded once.
Future<bool> confirmSignOut(BuildContext context, {String? account}) async {
  final colors = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Log out?', style: context.text.title),
      content: Text(
        account == null
            ? 'This device will be signed out and its message history removed '
                  'from this computer.'
            : 'Signs $account out on this device and removes its message '
                  'history from this computer.',
        style: context.text.subtitle,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Log Out', style: TextStyle(color: colors.danger)),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        IconButton(
          tooltip: 'Close settings',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.close, color: colors.textMuted),
        ),
        Text('ESC', style: context.text.fieldLabel),
      ],
    );
  }
}
