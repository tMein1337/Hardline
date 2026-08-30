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
    this.onSecondaryTap,
    this.onDoubleTap,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool isHovered) builder;
  final VoidCallback? onTap;

  /// Right-click. Every row that shows a person or a room is a place somebody
  /// will try this, so it lives here rather than being re-plumbed per widget.
  final VoidCallback? onSecondaryTap;

  /// Double-click.
  ///
  /// Pass this **only** when something is actually bound to it: a
  /// `GestureDetector` carrying both `onTap` and `onDoubleTap` holds every
  /// single tap for the double-tap timeout before firing it, which on a room
  /// list reads as the whole app being slow.
  final VoidCallback? onDoubleTap;

  final MouseCursor cursor;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  bool get _hasGesture =>
      widget.onTap != null ||
      widget.onSecondaryTap != null ||
      widget.onDoubleTap != null;

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
      child: _hasGesture
          ? GestureDetector(
              onTap: widget.onTap,
              onSecondaryTap: widget.onSecondaryTap,
              onDoubleTap: widget.onDoubleTap,
              behavior: HitTestBehavior.opaque,
              child: child,
            )
          : child,
    );
  }
}
