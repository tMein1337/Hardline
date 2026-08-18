// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Rebuilds its child with the current hover state.
///
/// The interface leans heavily on hover — row backgrounds, revealed timestamps,
/// morphing rail icons. Material's own hover handling is disabled in
/// `theme_builder.dart` (no ripples, transparent hover color) so those effects
/// are drawn explicitly instead, via this widget.
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool isHovered) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(context, _hovered);

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: widget.onTap == null
          ? child
          : GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: child,
            ),
    );
  }
}
