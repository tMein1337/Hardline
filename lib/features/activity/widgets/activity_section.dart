import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// A titled run of activity rows.
///
/// An empty section renders one muted line instead of collapsing, because
/// "nobody is in a call right now" and "this list is switched off in settings"
/// are different answers and a missing heading gives neither.
class ActivitySection extends StatelessWidget {
  const ActivitySection({
    super.key,
    required this.title,
    required this.icon,
    required this.emptyLabel,
    required this.children,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String emptyLabel;
  final List<Widget> children;

  /// Sits at the right of the heading — a count, or an action.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: colors.textFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: context.text.sectionHeader,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            child: Text(emptyLabel, style: context.text.timestamp),
          )
        else
          ...children,
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The shared shape of every activity row: avatar, two lines, a trailing bit.
///
/// One widget rather than three near-identical ones, so the sections line up
/// down the page — rows that each set their own insets drift apart within a
/// release or two, which is the same argument `SettingsPane` makes.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.onSecondaryTap,
    this.tooltip,
  });

  final Widget avatar;
  final Widget title;
  final Widget subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(context.metrics.rowRadius);

    // `Hoverable` is not reusable here: it owns the gesture detector too, and
    // it exposes no secondary tap, which every row here needs for "follow".
    Widget row = _Hover(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      builder: (hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        child: Container(
          decoration: BoxDecoration(
            color: hovered && onTap != null
                ? colors.listItemHover
                : Colors.transparent,
            borderRadius: radius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DefaultTextStyle(
                      style: context.text.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: title,
                    ),
                    const SizedBox(height: 1),
                    DefaultTextStyle(
                      style: context.text.timestamp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle,
                    ),
                  ],
                ),
              ),
              if (trailing case final widget?) ...[
                const SizedBox(width: 12),
                widget,
              ],
            ],
          ),
        ),
      ),
    );

    if (tooltip case final message?) {
      row = Tooltip(message: message, child: row);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: row,
    );
  }
}

class _Hover extends StatefulWidget {
  const _Hover({required this.cursor, required this.builder});

  final MouseCursor cursor;
  final Widget Function(bool hovered) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}
