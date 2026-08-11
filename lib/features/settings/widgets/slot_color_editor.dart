import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/discord_colors.dart';
import '../../../theme/theme_context.dart';

/// Edits one theme slot: HSV sliders plus a hex field, no package involved.
///
/// A picker dependency would be a lot of surface for three sliders, and the
/// hex field is the part people actually use — it is how a palette gets copied
/// out of a design tool.
///
/// Returns the chosen color, `_cleared` via [SlotColorResult.reset] when the
/// user asks for the preset's value back, or null on cancel.
class SlotColorEditor extends StatefulWidget {
  const SlotColorEditor({
    super.key,
    required this.slot,
    required this.initial,
    required this.hasOverride,
  });

  final String slot;
  final Color initial;

  /// Whether this slot currently differs from the preset, which is the only
  /// case where "Reset" means anything.
  final bool hasOverride;

  static Future<SlotColorResult?> show(
    BuildContext context, {
    required String slot,
    required Color initial,
    required bool hasOverride,
  }) => showDialog<SlotColorResult>(
    context: context,
    builder: (_) => SlotColorEditor(
      slot: slot,
      initial: initial,
      hasOverride: hasOverride,
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
    text: _hexOf(widget.initial),
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
      _hex.text = _hexOf(value.toColor());
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
        if (widget.hasOverride)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const SlotColorResult.reset()),
            child: Text(
              'Reset',
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

/// `#RRGGBB`, as a design tool would write it.
String _hexOf(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses `#RGB`-less hex in the two shapes people actually paste.
///
/// Null for anything unparseable, so a half-typed value leaves the preview
/// alone instead of flashing black on every keystroke.
Color? parseHexColor(String raw) {
  final text = raw.trim().replaceFirst('#', '');
  if (text.length != 6 && text.length != 8) return null;
  final value = int.tryParse(text, radix: 16);
  if (value == null) return null;
  // Six digits mean the user gave no alpha, and a theme slot is opaque unless
  // it says otherwise — defaulting to transparent would blank a whole surface.
  return Color(text.length == 6 ? 0xFF000000 | value : value);
}
