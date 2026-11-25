// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../emoji_data.dart';

const _pickerSize = Size(340, 380);

/// Opens the picker next to [anchor] (in global coordinates) and returns the
/// chosen reaction, or null if it was dismissed.
Future<String?> showReactionPicker(
  BuildContext context, {
  required Rect anchor,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close the reaction picker',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (context, _, _) => CustomSingleChildLayout(
      delegate: _BesideAnchor(anchor),
      child: const ReactionPicker(),
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Places the picker below [anchor] when it fits and above it otherwise,
/// right-aligned with it, and never off the window.
class _BesideAnchor extends SingleChildLayoutDelegate {
  const _BesideAnchor(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(
        Size(
          _pickerSize.width.clamp(0, constraints.maxWidth - 16),
          _pickerSize.height.clamp(0, constraints.maxHeight - 16),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    const margin = 8.0;
    final below = anchor.bottom + 4;
    final top = below + child.height + margin <= size.height
        ? below
        : anchor.top - child.height - 4;
    final left = anchor.right - child.width;
    return Offset(
      left.clamp(margin, size.width - child.width - margin),
      top.clamp(margin, size.height - child.height - margin),
    );
  }

  @override
  bool shouldRelayout(_BesideAnchor oldDelegate) =>
      anchor != oldDelegate.anchor;
}

/// Quick reactions, a search box and a grid of emoji.
///
/// Pops its route with the chosen key. Anything typed into the search box
/// that matches nothing can still be sent as it stands: the spec allows any
/// text as a reaction, and other clients send words.
class ReactionPicker extends StatefulWidget {
  const ReactionPicker({super.key});

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(String key) => Navigator.of(context).pop(key);

  /// The custom reaction offered when the search finds nothing — kept short,
  /// because a sentence as a reaction is a message in the wrong place.
  String? get _custom {
    final text = _query.trim();
    if (text.isEmpty || text.characters.length > 16) return null;
    return text;
  }

  void _submit() {
    final results = searchEmoji(_query);
    if (results.isNotEmpty) {
      _pick(results.first);
    } else if (_custom case final custom?) {
      _pick(custom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final results = _query.trim().isEmpty ? null : searchEmoji(_query);

    return Material(
      key: const Key('reaction_picker'),
      color: colors.floatingSurface,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.divider),
        ),
        padding: const EdgeInsets.all(8),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final emoji in quickReactions)
                    _EmojiCell(emoji: emoji, onTap: () => _pick(emoji)),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('reaction_picker_search'),
                controller: _search,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                onSubmitted: (_) => _submit(),
                style: context.text.inputText,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search emoji',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: colors.inputBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: results == null
                    ? _Grid(onPick: _pick)
                    : _Results(
                        results: results,
                        custom: _custom,
                        onPick: _pick,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final category in emojiCategories) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
            child: Text(
              category.name.toUpperCase(),
              style: context.text.sectionHeader,
            ),
          ),
          Wrap(
            children: [
              for (final entry in category.emoji)
                _EmojiCell(
                  emoji: entry.emoji,
                  tooltip: entry.keywords.split(' ').first,
                  onTap: () => onPick(entry.emoji),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.custom,
    required this.onPick,
  });

  final List<String> results;
  final String? custom;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (results.isNotEmpty) {
      return SingleChildScrollView(
        child: Wrap(
          children: [
            for (final emoji in results)
              _EmojiCell(emoji: emoji, onTap: () => onPick(emoji)),
          ],
        ),
      );
    }
    final custom = this.custom;
    if (custom == null) {
      return Center(
        child: Text('No emoji found', style: context.text.timestamp),
      );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: TextButton(
        key: const Key('reaction_picker_custom'),
        onPressed: () => onPick(custom),
        child: Text('React with “$custom”'),
      ),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  const _EmojiCell({required this.emoji, required this.onTap, this.tooltip});

  final String emoji;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cell = Hoverable(
      onTap: onTap,
      builder: (context, hovered) => Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? context.colors.listItemHover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
    return Semantics(label: tooltip ?? emoji, button: true, child: cell);
  }
}
