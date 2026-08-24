// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../overlay/hotkey_keys.dart';
import '../../overlay/overlay_channel.dart';
import '../../overlay/overlay_layout.dart';
import '../../overlay/overlay_prefs_controller.dart';
import '../../overlay/overlay_prefs_state.dart';
import '../../overlay/overlay_provider.dart';
import '../widgets/settings_layout.dart';

/// The always-on-top call overlay: whether it runs, where, and what it looks
/// like over each game.
///
/// The layout list is the part worth reading twice. A layout is a *named* thing
/// with executables pointed at it, not a property of one game — so a new game
/// can be handed a HUD that already exists instead of having one built for it,
/// and editing that HUD changes it everywhere at once.
class OverlayPane extends ConsumerWidget {
  const OverlayPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!OverlayChannel.isSupported) return const _Unsupported();

    final prefs = ref.watch(overlayPrefsProvider);
    final notifier = ref.read(overlayPrefsProvider.notifier);

    return SettingsPane(
      title: 'Call overlay',
      description:
          'Shows who is talking on top of a full-screen application, without '
          'leaving it.',
      children: [
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              SwitchListTile(
                value: prefs.enabled,
                onChanged: notifier.setEnabled,
                activeThumbColor: context.colors.accent,
                title: Text(
                  'Show the overlay during calls',
                  style: context.text.subtitle.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'It appears while you are in a call and stays out of the '
                  'way when nobody is speaking.',
                  style: context.text.timestamp,
                ),
              ),
              SwitchListTile(
                value: prefs.excludeFromCapture,
                onChanged: notifier.setExcludeFromCapture,
                activeThumbColor: context.colors.accent,
                title: Text(
                  'Hide it from screen shares',
                  style: context.text.subtitle.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'The overlay exists so you can see who is talking. Leaving '
                  'it in a shared screen shows everyone else a copy of '
                  'themselves.',
                  style: context.text.timestamp,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),
        // Stated here rather than left to be discovered, because the failure is
        // silent: the overlay is running correctly and simply cannot be seen.
        SettingsCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: context.colors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'An overlay can only be drawn over an application the '
                  'desktop compositor is still drawing. A game set to true '
                  'Fullscreen bypasses it, and nothing will appear — set the '
                  'game to Borderless or Windowed Fullscreen instead.',
                  style: context.text.subtitle,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const SettingsLabel('Placement'),
        SettingsCard(child: _MonitorPicker(prefs: prefs)),

        const SizedBox(height: 24),
        const SettingsLabel('Shortcuts'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HotkeyRow(
                label: 'Turn the overlay on and off',
                hotkey: prefs.toggleHotkey,
                onChanged: notifier.setToggleHotkey,
              ),
              const SettingsDivider(),
              _HotkeyRow(
                label: 'Move the overlay',
                hint:
                    'Lets you drag the overlay into place. The game loses '
                    'the foreground while you do, which is unavoidable — a '
                    'window that cannot be clicked cannot be arranged.',
                hotkey: prefs.editHotkey,
                onChanged: notifier.setEditHotkey,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const SettingsLabel('Layouts'),
        _LayoutList(prefs: prefs),

        const SizedBox(height: 24),
        const SettingsLabel('Which layout each game gets'),
        _Assignments(prefs: prefs),
      ],
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported();

  @override
  Widget build(BuildContext context) {
    return SettingsPane(
      title: 'Call overlay',
      children: [
        SettingsCard(
          child: Text(
            'The call overlay is only available on Windows at the moment. It '
            'is a layered always-on-top window driven from the Windows runner, '
            'and the equivalent has not been written for this platform yet.',
            style: context.text.subtitle,
          ),
        ),
      ],
    );
  }
}

class _MonitorPicker extends ConsumerStatefulWidget {
  const _MonitorPicker({required this.prefs});

  final OverlayPrefsState prefs;

  @override
  ConsumerState<_MonitorPicker> createState() => _MonitorPickerState();
}

class _MonitorPickerState extends ConsumerState<_MonitorPicker> {
  List<OverlayMonitor> _monitors = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final monitors = await ref
        .read(overlayControllerProvider)
        .channel
        .listMonitors();
    if (mounted) setState(() => _monitors = monitors);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notifier = ref.read(overlayPrefsProvider.notifier);

    // An empty id is a real choice, not a missing one: it means "wherever the
    // primary monitor is", which survives being unplugged and replugged in a
    // different port.
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Primary monitor')),
      for (final monitor in _monitors)
        if (!monitor.primary)
          DropdownMenuItem(value: monitor.id, child: Text(monitor.label)),
    ];
    final selected = items.any((item) => item.value == widget.prefs.monitorId)
        ? widget.prefs.monitorId
        : '';

    return Row(
      children: [
        Icon(Icons.monitor, size: 16, color: colors.textFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Monitor',
            style: context.text.subtitle.copyWith(color: colors.textPrimary),
          ),
        ),
        DropdownButton<String>(
          value: selected,
          items: items,
          dropdownColor: colors.floatingSurface,
          style: context.text.subtitle.copyWith(color: colors.textPrimary),
          underline: const SizedBox.shrink(),
          onChanged: (value) => notifier.setMonitor(value ?? ''),
        ),
      ],
    );
  }
}

/// A field that binds the next chord pressed into it.
class _HotkeyRow extends StatefulWidget {
  const _HotkeyRow({
    required this.label,
    required this.hotkey,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final OverlayHotkey hotkey;
  final ValueChanged<OverlayHotkey> onChanged;

  @override
  State<_HotkeyRow> createState() => _HotkeyRowState();
}

class _HotkeyRowState extends State<_HotkeyRow> {
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

    final hotkey = OverlayHotkey(
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
                      widget.onChanged(const OverlayHotkey.none()),
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

class _LayoutList extends ConsumerWidget {
  const _LayoutList({required this.prefs});

  final OverlayPrefsState prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final notifier = ref.read(overlayPrefsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final layout in prefs.layouts) ...[
          SettingsCard(
            child: _LayoutEditor(
              layout: layout,
              prefs: prefs,
              onChanged: (next, {bool write = true}) =>
                  notifier.updateLayout(next, write: write),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => notifier.addLayout(
              'Layout ${prefs.layouts.length + 1}',
              copyOf: prefs.layoutById(prefs.defaultLayoutId),
            ),
            icon: Icon(Icons.add, size: 16, color: colors.accent),
            label: Text('New layout', style: TextStyle(color: colors.accent)),
          ),
        ),
      ],
    );
  }
}

class _LayoutEditor extends ConsumerWidget {
  const _LayoutEditor({
    required this.layout,
    required this.prefs,
    required this.onChanged,
  });

  final OverlayLayout layout;
  final OverlayPrefsState prefs;
  final void Function(OverlayLayout layout, {bool write}) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final notifier = ref.read(overlayPrefsProvider.notifier);
    final isDefault = prefs.defaultLayoutId == layout.id;
    final users = prefs.executablesFor(layout.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: layout.name,
                style: context.text.subtitle.copyWith(
                  color: colors.textPrimary,
                ),
                decoration: const InputDecoration(isDense: true),
                onChanged: (value) =>
                    onChanged(layout.copyWith(name: value), write: false),
                onFieldSubmitted: (value) =>
                    onChanged(layout.copyWith(name: value)),
              ),
            ),
            const SizedBox(width: 8),
            if (isDefault)
              Tooltip(
                message: 'Anything without a layout of its own gets this one',
                child: Icon(Icons.star, size: 16, color: colors.accent),
              )
            else
              TextButton(
                onPressed: () => notifier.setDefaultLayout(layout.id),
                child: Text(
                  'Make default',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            IconButton(
              tooltip: 'Duplicate',
              iconSize: 16,
              icon: Icon(Icons.copy, color: colors.textFaint),
              onPressed: () =>
                  notifier.addLayout('${layout.name} copy', copyOf: layout),
            ),
            IconButton(
              tooltip: prefs.layouts.length <= 1
                  ? 'The last layout cannot be deleted'
                  : 'Delete',
              iconSize: 16,
              icon: Icon(Icons.delete_outline, color: colors.voiceControlDanger),
              onPressed: prefs.layouts.length <= 1
                  ? null
                  : () => notifier.removeLayout(layout.id),
            ),
          ],
        ),
        if (users.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'Used by ${users.join(', ')}',
              style: context.text.timestamp,
            ),
          ),
        _Slider(
          label: 'Avatar size',
          value: layout.avatarSize,
          min: kMinOverlayAvatar,
          max: kMaxOverlayAvatar,
          format: (value) => '${value.round()} px',
          onChanged: (value) =>
              onChanged(layout.copyWith(avatarSize: value), write: false),
          onCommit: (value) => onChanged(layout.copyWith(avatarSize: value)),
        ),
        _Slider(
          label: 'Visible when silent',
          value: layout.idleOpacity,
          min: 0,
          max: 1,
          format: (value) =>
              value == 0 ? 'Invisible' : '${(value * 100).round()}%',
          onChanged: (value) =>
              onChanged(layout.copyWith(idleOpacity: value), write: false),
          onCommit: (value) => onChanged(layout.copyWith(idleOpacity: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: layout.showNames,
          activeThumbColor: colors.accent,
          onChanged: (value) => onChanged(layout.copyWith(showNames: value)),
          title: Text(
            'Show names',
            style: context.text.subtitle.copyWith(color: colors.textPrimary),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: layout.horizontal,
          activeThumbColor: colors.accent,
          onChanged: (value) => onChanged(layout.copyWith(horizontal: value)),
          title: Text(
            'Lay people out across instead of down',
            style: context.text.subtitle.copyWith(color: colors.textPrimary),
          ),
        ),
        Text(
          'Position is set by dragging the overlay itself — '
          '${hotkeyLabel(prefs.editHotkey)}.',
          style: context.text.timestamp,
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    required this.onCommit,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: context.text.subtitle.copyWith(color: colors.textPrimary),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: colors.volumeSliderActive,
            inactiveColor: colors.volumeSliderTrack,
            // Live while dragging, written on release: a continuous gesture
            // emits far faster than a write is worth, and only the last value
            // is a decision. The same split the volume sliders use.
            onChanged: onChanged,
            onChangeEnd: onCommit,
          ),
        ),
        SizedBox(
          width: 70,
          child: Text(
            format(value),
            style: context.text.timestamp,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Which executable gets which layout, and the control that adds one.
class _Assignments extends ConsumerWidget {
  const _Assignments({required this.prefs});

  final OverlayPrefsState prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final notifier = ref.read(overlayPrefsProvider.notifier);
    final controller = ref.watch(overlayControllerProvider);
    final entries = prefs.assignments.keys.toList()..sort();

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entries.isEmpty)
            Text(
              'Every application uses the default layout. Assign one here to '
              'give a game its own — or to point several games at the same '
              'one, so a HUD you already like does not have to be rebuilt.',
              style: context.text.subtitle,
            ),
          for (final executable in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      executable,
                      style: context.text.subtitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: prefs.assignments[executable],
                    dropdownColor: colors.floatingSurface,
                    underline: const SizedBox.shrink(),
                    style: context.text.subtitle.copyWith(
                      color: colors.textPrimary,
                    ),
                    items: [
                      for (final layout in prefs.layouts)
                        DropdownMenuItem(
                          value: layout.id,
                          child: Text(layout.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) notifier.assign(executable, value);
                    },
                  ),
                  IconButton(
                    tooltip: 'Back to the default layout',
                    iconSize: 16,
                    icon: Icon(Icons.close, color: colors.textFaint),
                    onPressed: () => notifier.unassign(executable),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // The only way to name an application without asking somebody to type
          // an executable name from memory: whatever they last had in front of
          // them. Which, on the way back from a game, is the game.
          _AssignForeground(prefs: prefs, executable: controller.foregroundExecutable),
        ],
      ),
    );
  }
}

class _AssignForeground extends ConsumerWidget {
  const _AssignForeground({required this.prefs, required this.executable});

  final OverlayPrefsState prefs;
  final String executable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    if (executable.isEmpty || prefs.assignments.containsKey(executable)) {
      return Text(
        'Switch to a game and back, then it can be assigned here.',
        style: context.text.timestamp,
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            'Last application you were in: $executable',
            style: context.text.subtitle,
          ),
        ),
        DropdownButton<String>(
          hint: Text('Assign…', style: TextStyle(color: colors.accent)),
          value: null,
          dropdownColor: colors.floatingSurface,
          underline: const SizedBox.shrink(),
          items: [
            for (final layout in prefs.layouts)
              DropdownMenuItem(value: layout.id, child: Text(layout.name)),
          ],
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(overlayPrefsProvider.notifier)
                .assign(executable, value);
          },
        ),
      ],
    );
  }
}
