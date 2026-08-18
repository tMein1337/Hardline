// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// One pane of the settings screen: a title and a scrolling body.
///
/// Every pane goes through this so they share their measurements. Panes that
/// set their own padding drift apart from each other within a release or two.
class SettingsPane extends StatelessWidget {
  const SettingsPane({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  /// Wide enough for a device row, narrow enough that text does not run across
  /// a maximised window in one line.
  static const maxContentWidth = 660.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 60, 40, 80),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: context.text.title.copyWith(fontSize: 20)),
              if (description case final text?) ...[
                const SizedBox(height: 6),
                Text(text, style: context.text.subtitle),
              ],
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Small caps label above a run of related settings.
class SettingsLabel extends StatelessWidget {
  const SettingsLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(), style: context.text.fieldLabel),
  );
}

/// A raised block grouping controls that belong together.
///
/// A `Material` rather than a `Container`, so the card *is* the nearest
/// material ancestor for whatever sits in it. With a plain coloured container,
/// a `ListTile` or `InkWell` inside paints its background and ink on some
/// material further up — behind the card's own opaque background, where none of
/// it can be seen. Flutter asserts about exactly this, and the app only got
/// away with it because splashes are globally disabled.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.elevatedSurface,
      // `shape` draws the fill and the outline together, so the border does not
      // need a second box of its own.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.metrics.rowRadius * 2),
        side: BorderSide(color: colors.divider),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// A labelled row with a control on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading case final widget?) ...[widget, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.username),
              if (subtitle case final text?) ...[
                const SizedBox(height: 2),
                Text(text, style: context.text.subtitle),
              ],
            ],
          ),
        ),
        if (trailing case final widget?) ...[
          const SizedBox(width: 16),
          widget,
        ],
      ],
    );
  }
}

/// A small run of mutually exclusive options.
///
/// Hand-rolled rather than `SegmentedButton` because the theme extension styles
/// the app's own widgets, not Material's — a stock segmented button arrives
/// with its own colour scheme and does not follow the palette.
class SettingsChoice<T> extends StatelessWidget {
  const SettingsChoice({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(context.metrics.rowRadius);

    return Wrap(
      spacing: 8,
      children: [
        for (final value in values)
          Material(
            color: value == selected
                ? colors.accent
                : colors.floatingSurface,
            borderRadius: radius,
            child: InkWell(
              onTap: () => onChanged(value),
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(
                  labelOf(value),
                  style: context.text.buttonLabel.copyWith(
                    color: value == selected
                        ? colors.textOnAccent
                        : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Separator inside a [SettingsCard].
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 32, color: context.colors.divider);
}
