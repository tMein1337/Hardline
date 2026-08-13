import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme_state.dart';
import '../../../theme/discord_colors.dart';
import '../../../theme/discord_palettes.dart';
import '../../../theme/theme_context.dart';
import '../../../theme/theme_controller.dart';
import '../../../theme/theme_entry.dart';
import '../../../theme/theme_library.dart';
import '../widgets/settings_layout.dart';
import '../widgets/slot_color_editor.dart';
import '../widgets/theme_library_card.dart';

/// The theme library, and the colours of whichever theme is selected.
///
/// The grid renders from [DiscordSlot.all] rather than a hardcoded list, so a
/// slot added to the palette becomes editable here without anyone remembering
/// to come back. That property is inherited from the development swatch page
/// this replaces, and is the reason it was written that way in the first place.
///
/// Edits land in the active theme itself, not in a patch on top of it: what is
/// on screen is what an export writes out.
class AppearancePane extends ConsumerWidget {
  const AppearancePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final library = ref.watch(themeLibraryProvider);
    // The library keeps itself non-empty, so the fallback is a formality —
    // but `presetId` can name a theme that was deleted in the same frame.
    final active = library.byId(theme.presetId) ?? library.entries.firstOrNull;

    return SettingsPane(
      title: 'Appearance',
      description:
          'Changes apply immediately across the whole app and are remembered '
          'on this computer.',
      children: [
        const ThemeLibraryCard(),
        if (theme.overrides.isNotEmpty) ...[
          const SizedBox(height: 12),
          _LegacyOverridesCard(count: theme.overrides.length),
        ],
        const SizedBox(height: 24),
        const SettingsLabel('Tooltips'),
        _TooltipDelayCard(delay: theme.tooltipDelay),
        const SizedBox(height: 24),
        if (active != null) ...[
          SettingsLabel('Colors · ${active.name}'),
          GridView.builder(
            shrinkWrap: true,
            // The pane already scrolls; a second scrollable inside it would
            // trap the wheel over the grid.
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisExtent: 64,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: DiscordSlot.all.length,
            itemBuilder: (context, index) {
              final slot = DiscordSlot.all[index];
              return _SwatchTile(
                slot: slot,
                changed: _divergesFromBuiltIn(active, slot),
                onEdit: () => _edit(context, ref, active.id, slot),
              );
            },
          ),
        ],
      ],
    );
  }

  /// Whether [slot] has moved away from the built-in palette this theme was
  /// seeded from. False for a theme the user made or imported — it was never a
  /// copy of anything, so "changed" would have nothing to mean.
  static bool _divergesFromBuiltIn(ThemeEntry entry, String slot) {
    final builtIn = DiscordPalettes.byIdMap[entry.id];
    if (builtIn == null) return false;
    return entry.colors[slot] != builtIn.slot(slot).toARGB32();
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String themeId,
    String slot,
  ) async {
    final library = ref.read(themeLibraryProvider);
    final entry = library.byId(themeId);
    if (entry == null) return;

    final result = await SlotColorEditor.show(
      context,
      slot: slot,
      initial: ref.read(discordColorsProvider).slot(slot),
      canRevert: _divergesFromBuiltIn(entry, slot),
    );
    if (result == null) return;

    final controller = ref.read(themeLibraryProvider.notifier);
    if (result.reset) {
      await controller.revertSlot(themeId, slot);
    } else if (result.color case final color?) {
      await controller.setSlot(themeId, slot, color);
    }
  }
}

/// The one-time offer to keep colours customised before themes were saveable.
///
/// Shows only while `AppThemeState.overrides` is non-empty, which after this is
/// answered is never again — see the field's own comment. Without it, upgrading
/// would either silently revert those colours or leave them editable from
/// nowhere, with the grid showing values that no theme in the list contains.
class _LegacyOverridesCard extends ConsumerWidget {
  const _LegacyOverridesCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRow(
            leading: Icon(Icons.info_outline, color: colors.warning, size: 20),
            title: count == 1
                ? '1 colour customisation from an earlier version'
                : '$count colour customisations from an earlier version',
            subtitle:
                'These were made before themes could be named and saved, and '
                'currently sit on top of whichever theme is selected. Keep '
                'them as a theme of their own, or drop them.',
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    ref.read(themeControllerProvider.notifier).clearAllOverrides(),
                child: Text('Discard', style: TextStyle(color: colors.textMuted)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _save(ref),
                child: const Text('Save as a theme'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Snapshots what is *currently on screen* — preset plus patch — so the new
  /// theme is indistinguishable from what the user has been looking at.
  Future<void> _save(WidgetRef ref) async {
    final library = ref.read(themeLibraryProvider);
    final presetId = ref.read(themeControllerProvider).presetId;
    final source = library.byId(presetId);

    final id = ref
        .read(themeLibraryProvider.notifier)
        .add(
          ThemeEntry.fromColors(
            id: generateThemeId(),
            name: '${source?.name ?? 'Theme'} (customised)',
            colors: ref.read(discordColorsProvider),
          ),
        );

    await ref.read(themeControllerProvider.notifier).setPreset(id);
    // Last, and only once the theme exists: clearing first would repaint the
    // app without the customisations, and the snapshot would be of the wrong
    // colours.
    await ref.read(themeControllerProvider.notifier).clearAllOverrides();
  }
}

/// How long the pointer has to rest on something before its tooltip appears.
///
/// A live preview sits next to the slider, because the only way to judge a
/// hover delay is to hover something and count — a number in milliseconds tells
/// nobody anything.
class _TooltipDelayCard extends ConsumerWidget {
  const _TooltipDelayCard({required this.delay});

  final Duration delay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(themeControllerProvider.notifier);
    final milliseconds = delay.inMilliseconds;

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRow(
            title: 'Hover delay',
            subtitle: milliseconds == 0
                ? 'Tooltips appear immediately.'
                : 'Tooltips appear after ${_format(milliseconds)}.',
            trailing: Tooltip(
              message: 'This is what a tooltip looks like.',
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('Hover me'),
              ),
            ),
          ),
          Slider(
            value: milliseconds.toDouble(),
            max: kMaxTooltipDelay.inMilliseconds.toDouble(),
            // 50ms steps: finer than anyone can perceive, coarse enough that
            // the slider lands on round numbers.
            divisions: kMaxTooltipDelay.inMilliseconds ~/ 50,
            label: milliseconds == 0 ? 'Instant' : _format(milliseconds),
            // Dragging updates the theme live so the preview button reacts
            // under the pointer; only the release is written to disk.
            onChanged: (value) => controller.setTooltipDelay(
              Duration(milliseconds: value.round()),
              commit: false,
            ),
            onChangeEnd: (value) => controller.setTooltipDelay(
              Duration(milliseconds: value.round()),
            ),
          ),
          Row(
            children: [
              Text('Instant', style: context.text.timestamp),
              const Spacer(),
              Text(
                _format(kMaxTooltipDelay.inMilliseconds),
                style: context.text.timestamp,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _format(int milliseconds) => milliseconds % 1000 == 0
      ? '${milliseconds ~/ 1000} s'
      : '${(milliseconds / 1000).toStringAsFixed(2)} s';
}

class _SwatchTile extends ConsumerWidget {
  const _SwatchTile({
    required this.slot,
    required this.changed,
    required this.onEdit,
  });

  final String slot;

  /// Whether this slot has been moved away from the built-in palette the theme
  /// was seeded from. Always false once the theme is one of the user's own.
  final bool changed;

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final value = colors.slot(slot);
    final radius = BorderRadius.circular(context.metrics.rowRadius);

    return Material(
      color: colors.elevatedSurface,
      borderRadius: radius,
      child: InkWell(
        onTap: onEdit,
        borderRadius: radius,
        hoverColor: colors.listItemHover,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              // The marker is a border rather than a badge so a customised slot
              // is findable by scanning the grid, which is how someone hunts
              // down the one change they regret.
              color: changed ? colors.accent : colors.divider,
              width: changed ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: value,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.dividerStrong),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DiscordSlot.labelOf(slot),
                      style: context.text.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '#${value.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                      style: context.text.timestamp,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
