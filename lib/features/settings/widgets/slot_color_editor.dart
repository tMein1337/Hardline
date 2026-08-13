import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/discord_colors.dart';
import '../../../theme/hex_color.dart';
import '../../../theme/theme_context.dart';

/// Edits one theme slot: HSV sliders plus a hex field, no package involved.
///
/// A picker dependency would be a lot of surface for three sliders, and the
/// hex field is the part people actually use — it is how a palette gets copied
/// out of a design tool.
///
/// Returns the chosen color, the built-in value via [SlotColorResult.reset]
/// when the user asks for it back, or null on cancel.
class SlotColorEditor extends StatefulWidget {
  const SlotColorEditor({
    super.key,
    required this.slot,
    required this.initial,
    required this.canRevert,
  });

  final String slot;
  final Color initial;

  /// Whether this theme still tracks a built-in palette *and* has moved this
  /// slot away from it — the only case where "Reset" has a value to name.
  ///
  /// False for a theme the user made or imported: it was never a copy of
  /// anything, so there is nothing to go back to. Duplicating before
  /// experimenting is what covers that case.
  final bool canRevert;

  static Future<SlotColorResult?> show(
    BuildContext context, {
    required String slot,
    required Color initial,
    required bool canRevert,
  }) => showDialog<SlotColorResult>(
    context: context,
    builder: (_) => SlotColorEditor(
      slot: slot,
      initial: initial,
      canRevert: canRevert,
    ),
  );

  @override
  State<SlotColorEditor> createState() => _SlotColorEditorState();
}

/// What the editor was closed with.
@immutable
class SlotColorResult {
  const SlotColorResult.color(this.color) : reset = false;
  const SlotColorResult.reset() : color = null, reset = true;

  final Color? color;
  final bool reset;
}

class _SlotColorEditorState extends State<SlotColorEditor> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: hexRgbOf(widget.initial),
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _setFromSliders(HSVColor value) {
    setState(() {
      _hsv = value;
      // Keeps the field in step without fighting the user: it is only rewritten
      // when a slider moved, never while they are typing into it.
      _hex.text = hexRgbOf(value.toColor());
    });
  }

  void _setFromHex(String raw) {
    final parsed = parseHexColor(raw);
    if (parsed == null) return;
    setState(() => _hsv = HSVColor.fromColor(parsed));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text(DiscordSlot.labelOf(widget.slot), style: context.text.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(context.metrics.rowRadius),
                border: Border.all(color: colors.dividerStrong),
              ),
            ),
            const SizedBox(height: 16),
            _Slider(
              label: 'Hue',
              value: _hsv.hue,
              max: 360,
              onChanged: (v) => _setFromSliders(_hsv.withHue(v)),
            ),
            _Slider(
              label: 'Saturation',
              value: _hsv.saturation,
              max: 1,
              onChanged: (v) => _setFromSliders(_hsv.withSaturation(v)),
            ),
            _Slider(
              label: 'Brightness',
              value: _hsv.value,
              max: 1,
              onChanged: (v) => _setFromSliders(_hsv.withValue(v)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hex,
              style: context.text.inputText,
              // Long enough for #AARRGGBB; the parser accepts either length.
              maxLength: 9,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
              ],
              decoration: InputDecoration(
                labelText: 'Hex',
                counterText: '',
                labelStyle: context.text.fieldLabel,
                filled: true,
                fillColor: colors.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    context.metrics.rowRadius,
                  ),
                  borderSide: BorderSide(color: colors.inputBorder),
                ),
              ),
              onChanged: _setFromHex,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.canRevert)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const SlotColorResult.reset()),
            child: Text(
              'Reset to built-in',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(SlotColorResult.color(_color)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(label, style: context.text.subtitle),
        ),
        Expanded(
          child: Slider(value: value.clamp(0, max), max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

