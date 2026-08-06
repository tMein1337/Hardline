import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// The wash drawn over the chat while a file is being dragged onto it.
///
/// Purely decorative — the caller wraps it in an [IgnorePointer] so it can
/// never swallow the drop it is advertising.
class AttachmentDropOverlay extends StatelessWidget {
  const AttachmentDropOverlay({super.key, required this.roomName});

  final String roomName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;

    return Container(
      color: colors.dropOverlay,
      padding: EdgeInsets.all(metrics.contentPadding),
      child: _OutlineBox(
        color: colors.dropBorder,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.upload_file, size: 48, color: colors.dropBorder),
              const SizedBox(height: 12),
              Text(
                'Upload to #$roomName',
                style: context.text.title.copyWith(color: colors.textHeader),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded outline in [color], drawn around [child].
class _OutlineBox extends StatelessWidget {
  const _OutlineBox({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
