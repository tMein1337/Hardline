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
              Text(title, style: context.text.title.copyWith(fontSize: context.text.sized(20))),
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
    this.hint,
    this.trailing,
    this.leading,
  });

  final String title;
  final String? subtitle;

  /// Explanation shown on hover instead of under the title. See [SettingsHint].
  final String? hint;

  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final row = _row(context);
    return hint == null ? row : SettingsHint(message: hint!, child: row);
  }

  Widget _row(BuildContext context) {
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

/// A switch with a label, and the one place a settings toggle should be built.
///
/// Before this existed every toggle was a raw `SwitchListTile` written out at
/// the call site, and they had drifted: some named an active colour, some let
/// Material pick one, and the padding differed pane to pane. The switch colour
/// now comes from `switchTheme` in `theme_builder.dart`, so nothing here names
/// it either.
///
/// [subtitle] and [hint] are the same choice [SettingsRow] offers, and the rule
/// is the one in [SettingsHint]: a warning about what the switch will do stays
/// on the page as a [subtitle]; a description of what it is for goes behind a
/// [hint]. Passing both is allowed but usually means the text wants splitting.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.value,
    required this.title,
    required this.onChanged,
    this.subtitle,
    this.hint,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final bool value;
  final String title;

  /// Shown under the title, on the page. For text that has to be read *before*
  /// the switch is touched.
  final String? subtitle;

  /// Shown on hover. For text that explains rather than warns.
  final String? hint;

  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final tile = SwitchListTile(
      contentPadding: contentPadding,
      value: value,
      title: Text(title, style: context.text.messageBody),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: context.text.timestamp),
      onChanged: onChanged,
    );

    return hint == null ? tile : SettingsHint(message: hint!, child: tile);
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

/// Puts an explanation behind a hover rather than under the control.
///
/// Settings panes accumulate prose: every switch grows a paragraph saying what
/// it does and why, and a screen of those is harder to read than a screen of
/// labels. A hint moves the paragraph to a tooltip, where somebody who wants it
/// can find it and somebody scanning for a switch is not made to read past it.
///
/// **Not everything belongs here.** A warning about what a control will do is
/// read *before* the click or not at all; a live readout of a value is the
/// point of the row rather than an aside about it; and a security claim hidden
/// behind a hover is a security claim nobody sees. Those stay on the page. The
/// test is roughly: would somebody who never hovers be worse off than annoyed?
class SettingsHint extends StatelessWidget {
  const SettingsHint({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      // A rich message rather than a plain one, only so the text can be given
      // a width. `Tooltip` otherwise wraps at the window edge, and these run
      // long enough to become a single unreadable band across a maximised
      // window. Delay and styling still come from the theme, which is what
      // keeps the tooltip-delay setting in charge of all of them.
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(message, style: Theme.of(context).tooltipTheme.textStyle),
        ),
      ),
      child: child,
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
