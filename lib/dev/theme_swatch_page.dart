import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/discord_colors.dart';
import '../theme/discord_palettes.dart';
import '../theme/theme_context.dart';
import '../theme/theme_controller.dart';

/// Temporary development screen: renders every color slot and exercises the
/// preset/override/persistence paths.
///
/// This is the harness that proves the theming layer works before any real UI
/// depends on it. It is removed once the app shell lands, but it is also a
/// preview of what the eventual settings screen looks like — note that it
/// renders itself from [DiscordSlot.all] rather than a hardcoded list, so new
/// slots appear automatically.
class ThemeSwatchPage extends ConsumerWidget {
  const ThemeSwatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final themeState = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);

    return Scaffold(
      backgroundColor: colors.chatBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme slots', style: context.text.title),
                  const SizedBox(height: 4),
                  Text(
                    '${DiscordSlot.all.length} slots · preset '
                    '"${themeState.presetId}" · '
                    '${themeState.overrides.length} override(s)',
                    style: context.text.subtitle,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in DiscordPalettes.labels.entries)
                        _PresetButton(
                          label: entry.value,
                          selected: themeState.presetId == entry.key,
                          onTap: () => controller.setPreset(entry.key),
                        ),
                      _PresetButton(
                        label: 'Override accent → green',
                        selected: themeState.overrides.containsKey(
                          DiscordSlot.accent,
                        ),
                        // Sourced from the palette, not a literal — the "no hex
                        // outside lib/theme" rule applies here too.
                        onTap: () => controller.setOverride(
                          DiscordSlot.accent,
                          colors.success,
                        ),
                      ),
                      _PresetButton(
                        label: 'Reset',
                        selected: false,
                        onTap: controller.resetToDefaults,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(color: colors.divider, height: 1),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260,
                      mainAxisExtent: 64,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                itemCount: DiscordSlot.all.length,
                itemBuilder: (context, index) {
                  final slot = DiscordSlot.all[index];
                  return _SwatchTile(slot: slot);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwatchTile extends StatelessWidget {
  const _SwatchTile({required this.slot});

  final String slot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = colors.slot(slot);

    return Container(
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        borderRadius: BorderRadius.circular(context.metrics.rowRadius),
        border: Border.all(color: colors.divider),
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
      color: selected ? colors.accent : colors.elevatedSurface,
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
