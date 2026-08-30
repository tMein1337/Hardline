// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme_context.dart';
import '../../hotkeys/hotkey.dart';
import '../../hotkeys/hotkey_keys.dart';

/// A field that binds the next chord pressed into it.
///
/// Shared by the overlay pane and the voice pane, which bind different
/// actions through different controllers but ask exactly the same
/// question — and would otherwise each need their own copy of the rules
/// about which chords Windows will accept.
class HotkeyRow extends StatefulWidget {
  const HotkeyRow({
    super.key,
    required this.label,
    required this.hotkey,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final Hotkey hotkey;
  final ValueChanged<Hotkey> onChanged;

  @override
  State<HotkeyRow> createState() => HotkeyRowState();
}

class HotkeyRowState extends State<HotkeyRow> {
  final _focus = FocusNode();
  bool _capturing = false;
  String? _refused;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _capturing = false;
        _refused = null;
      });
      _focus.unfocus();
      return KeyEventResult.handled;
    }

    final key = virtualKeyFor(event.logicalKey);
    // Modifiers arrive as key presses of their own while the chord is being
    // built. Ignoring them is what lets somebody hold Ctrl+Shift and then reach
    // for the letter.
    if (key == null) return KeyEventResult.handled;

    final hotkey = Hotkey(
      modifiers: modifiersFrom(HardwareKeyboard.instance.logicalKeysPressed),
      key: key,
    );

    if (!isBindable(hotkey)) {
      setState(
        () => _refused =
            'A letter or digit on its own would be taken from every other '
            'program on the machine. Add Ctrl, Alt or Shift — or use a '
            'function key.',
      );
      return KeyEventResult.handled;
    }

    setState(() {
      _capturing = false;
      _refused = null;
    });
    _focus.unfocus();
    widget.onChanged(hotkey);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: context.text.subtitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Focus(
                focusNode: _focus,
                onKeyEvent: _onKey,
                onFocusChange: (focused) {
                  if (!focused && _capturing) {
                    setState(() => _capturing = false);
                  }
                },
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _capturing = true;
                      _refused = null;
                    });
                    _focus.requestFocus();
                  },
                  child: Text(
                    _capturing ? 'Press a chord…' : hotkeyLabel(widget.hotkey),
                    style: TextStyle(
                      color: _capturing ? colors.accent : colors.textPrimary,
                    ),
                  ),
                ),
              ),
              if (widget.hotkey.isBound) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Unbind',
                  iconSize: 16,
                  icon: Icon(Icons.close, color: colors.textFaint),
                  onPressed: () =>
                      widget.onChanged(const Hotkey.none()),
                ),
              ],
            ],
          ),
          if (_refused != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _refused!,
                style: context.text.timestamp.copyWith(color: colors.warning),
              ),
            )
          else if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(widget.hint!, style: context.text.timestamp),
            ),
        ],
      ),
    );
  }
}

