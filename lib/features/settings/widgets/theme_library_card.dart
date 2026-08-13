import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/discord_colors.dart';
import '../../../theme/theme_context.dart';
import '../../../theme/theme_controller.dart';
import '../../../theme/theme_entry.dart';
import '../../../theme/theme_file_io.dart';
import '../../../theme/theme_library.dart';
import 'settings_layout.dart';
import 'text_prompt.dart';

/// The theme list: one row per theme, with everything that can be done to one.
///
/// Actions are inline icon buttons rather than an overflow menu, because this
/// app has no popup menus anywhere — a `PopupMenuButton` arrives with Material's
/// own colour scheme rather than the palette, the same problem
/// `SettingsChoice` exists to avoid for segmented buttons.
class ThemeLibraryCard extends ConsumerWidget {
  const ThemeLibraryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(themeLibraryProvider);
    final activeId = ref.watch(
      themeControllerProvider.select((state) => state.presetId),
    );
    final missing = library.missingSeededIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SettingsLabel('Themes')),
            TextButton.icon(
              onPressed: () => _import(context, ref),
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: const Text('Import…'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New theme'),
            ),
          ],
        ),
        SettingsCard(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              for (final entry in library.entries)
                _ThemeRow(
                  entry: entry,
                  active: entry.id == activeId,
                  // The last theme cannot be deleted: `presetId` would name
                  // nothing and the list would offer no way back.
                  deletable: library.entries.length > 1,
                ),
            ],
          ),
        ),
        if (missing.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  ref.read(themeLibraryProvider.notifier).restoreBuiltIns(),
              icon: const Icon(Icons.settings_backup_restore, size: 16),
              label: Text(
                missing.length == 1
                    ? 'Restore 1 built-in theme'
                    : 'Restore ${missing.length} built-in themes',
              ),
            ),
          ),
      ],
    );
  }

  /// Duplicates the active theme under a name the user gives.
  ///
  /// A copy rather than a blank palette: an "empty" theme would be sixty
  /// magenta slots and hours of work before it was usable, whereas every real
  /// theme starts life as a small change to one that already works.
  static Future<void> _create(BuildContext context, WidgetRef ref) async {
    final library = ref.read(themeLibraryProvider);
    final source = library.byId(ref.read(themeControllerProvider).presetId) ??
        library.entries.firstOrNull;
    if (source == null) return;

    final name = await promptForText(
      context,
      title: 'New theme',
      description:
          'Starts as a copy of "${source.name}". Every colour can be changed '
          'afterwards, and the original is left alone.',
      hint: 'Theme name',
      initial: '${source.name} (copy)',
      confirmLabel: 'Create',
    );
    if (name == null || name.isEmpty || !context.mounted) return;

    final controller = ref.read(themeLibraryProvider.notifier);
    final id = controller.duplicate(source.id);
    await controller.rename(id, name);
    await ref.read(themeControllerProvider.notifier).setPreset(id);
  }

  static Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ThemeEntry? imported;
    try {
      imported = await importTheme();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeThemeFileError(error))),
      );
      return;
    }
    // A cancelled dialog is not an error and says nothing.
    if (imported == null) return;

    final id = ref.read(themeLibraryProvider.notifier).add(imported);
    await ref.read(themeControllerProvider.notifier).setPreset(id);
    // Read back rather than trusting `imported.name`: `add` renames on a
    // collision, and the message must say what is actually in the list.
    final stored = ref.read(themeLibraryProvider).byId(id);
    messenger.showSnackBar(
      SnackBar(content: Text('Imported "${stored?.name ?? imported.name}".')),
    );
  }
}

class _ThemeRow extends ConsumerWidget {
  const _ThemeRow({
    required this.entry,
    required this.active,
    required this.deletable,
  });

  final ThemeEntry entry;
  final bool active;
  final bool deletable;

  /// The five slots that tell two themes apart at a glance: the three surfaces
  /// stacked left to right as they are on screen, then the accent and the text.
  static const _previewSlots = [
    DiscordSlot.serverRail,
    DiscordSlot.channelSidebar,
    DiscordSlot.chatBackground,
    DiscordSlot.accent,
    DiscordSlot.textPrimary,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final radius = BorderRadius.circular(context.metrics.rowRadius);
    final preview = entry.toColors();

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? colors.listItemSelected : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: active
              ? null
              : () =>
                    ref.read(themeControllerProvider.notifier).setPreset(entry.id),
          borderRadius: radius,
          hoverColor: colors.listItemHover,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              children: [
                Icon(
                  active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: active ? colors.accent : colors.textFaint,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.name,
                    style: active
                        ? context.text.channelNameActive
                        : context.text.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                for (final slot in _previewSlots) ...[
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: preview.slot(slot),
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.dividerStrong),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 8),
                _Action(
                  icon: Icons.drive_file_rename_outline,
                  tooltip: 'Rename',
                  onPressed: () => _rename(context, ref),
                ),
                _Action(
                  icon: Icons.content_copy_outlined,
                  tooltip: 'Duplicate',
                  onPressed: () => _duplicate(ref),
                ),
                _Action(
                  icon: Icons.save_alt,
                  tooltip: 'Export to a file',
                  onPressed: () => _export(context),
                ),
                _Action(
                  icon: Icons.delete_outline,
                  tooltip: deletable
                      ? 'Delete'
                      : 'The last theme cannot be deleted',
                  color: colors.danger,
                  onPressed: deletable ? () => _delete(context, ref) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptForText(
      context,
      title: 'Rename theme',
      initial: entry.name,
      hint: 'Theme name',
      confirmLabel: 'Rename',
    );
    if (name == null || name.isEmpty) return;
    await ref.read(themeLibraryProvider.notifier).rename(entry.id, name);
  }

  /// Switches to the copy, so the next colour change lands in it.
  ///
  /// Duplicating and then editing the original by mistake is the trap this
  /// avoids, and it is silent when it happens — the theme you meant to protect
  /// is the one that changes.
  Future<void> _duplicate(WidgetRef ref) async {
    final id = ref.read(themeLibraryProvider.notifier).duplicate(entry.id);
    await ref.read(themeControllerProvider.notifier).setPreset(id);
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await exportTheme(entry);
      if (path == null) return;
      messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeThemeFileError(error))),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.floatingSurface,
        title: Text('Delete "${entry.name}"?', style: context.text.title),
        content: Text(
          entry.isSeeded
              ? 'This is one of the built-in themes. It can be put back later '
                    'with "Restore built-in themes", but any changes you have '
                    'made to it are lost.'
              : 'Its colours are lost unless you have exported it to a file.',
          style: context.text.subtitle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Work out where to land *before* removing, while the neighbour is still
    // findable. Deleting the active theme would otherwise leave `presetId`
    // naming nothing, which renders as the fallback palette with no row
    // selected — the app looks like it lost the setting rather than the theme.
    final library = ref.read(themeLibraryProvider);
    final index = library.indexOf(entry.id);
    final neighbour = index + 1 < library.entries.length
        ? library.entries[index + 1]
        : library.entries[index - 1];
    final wasActive = ref.read(themeControllerProvider).presetId == entry.id;

    await ref.read(themeLibraryProvider.notifier).remove(entry.id);
    if (wasActive) {
      await ref.read(themeControllerProvider.notifier).setPreset(neighbour.id);
    }
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      color: color ?? colors.textMuted,
      disabledColor: colors.textFaint.withValues(alpha: 0.4),
    );
  }
}
