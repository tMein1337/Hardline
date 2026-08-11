import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme_state.dart';
import '../../../theme/discord_colors.dart';
import '../../../theme/discord_palettes.dart';
import '../../../theme/theme_context.dart';
import '../../../theme/theme_controller.dart';
import '../widgets/settings_layout.dart';
import '../widgets/slot_color_editor.dart';

/// Preset picker and per-slot color overrides.
///
/// Renders from [DiscordSlot.all] rather than a hardcoded list, so a slot added
/// to the palette becomes editable here without anyone remembering to come
/// back. That property is inherited from the development swatch page this
/// replaces, and is the reason it was written that way in the first place.
class AppearancePane extends ConsumerWidget {
  const AppearancePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);
    final overrides = theme.overrides;

    return SettingsPane(
      title: 'Appearance',
      description:
          'Changes apply immediately across the whole app and are remembered '
          'on this computer.',
      children: [
        const SettingsLabel('Theme'),
        SettingsCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in DiscordPalettes.labels.entries)
                _PresetButton(
                  label: entry.value,
                  selected: theme.presetId == entry.key,
                  onTap: () => controller.setPreset(entry.key),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SettingsLabel('Tooltips'),
        _TooltipDelayCard(delay: theme.tooltipDelay),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: SettingsLabel(
                overrides.isEmpty
                    ? 'Colors'
                    : 'Colors · ${overrides.length} customised',
              ),
            ),
            if (overrides.isNotEmpty)
              TextButton(
                onPressed: controller.clearAllOverrides,
                child: Text(
                  'Reset all',
                  style: TextStyle(color: context.colors.textMuted),
                ),
              ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          // The pane already scrolls; a second scrollable inside it would trap
          // the wheel over the grid.
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
              overridden: overrides.containsKey(slot),
              onEdit: () => _edit(context, ref, slot),
            );
          },
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String slot,
  ) async {
    final controller = ref.read(themeControllerProvider.notifier);
    final overridden = ref
        .read(themeControllerProvider)
        .overrides
        .containsKey(slot);

    final result = await SlotColorEditor.show(
      context,
      slot: slot,
      initial: ref.read(discordColorsProvider).slot(slot),
      hasOverride: overridden,
    );
    if (result == null) return;

    if (result.reset) {
      await controller.clearOverride(slot);
    } else if (result.color case final color?) {
      await controller.setOverride(slot, color);
    }
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
    required this.overridden,
    required this.onEdit,
  });

  final String slot;
  final bool overridden;
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
              color: overridden ? colors.accent : colors.divider,
              width: overridden ? 2 : 1,
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

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.accent : colors.floatingSurface,
      borderRadius: BorderRadius.circular(context.metrics.rowRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.metrics.rowRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: context.text.buttonLabel.copyWith(
              color: selected ? colors.textOnAccent : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
