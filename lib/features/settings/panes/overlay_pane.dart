// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../hotkeys/hotkey.dart';
import '../../hotkeys/hotkey_action.dart';
import '../../hotkeys/hotkey_keys.dart';
import '../../hotkeys/hotkey_provider.dart';
import '../../hotkeys/hotkeys_controller.dart';
import '../widgets/hotkey_row.dart';
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
              Icon(Icons.info_outline, size: 16, color: context.colors.warning),
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
        const SettingsLabel('Fading'),
        SettingsCard(child: _LingerCard(linger: prefs.linger)),

        const SizedBox(height: 24),
        const SettingsLabel('Placement'),
        SettingsCard(child: _MonitorPicker(prefs: prefs)),

        const SizedBox(height: 24),
        const SettingsLabel('Shortcuts'),
        // Said out loud because the alternative is somebody wondering why
        // their chord does nothing: a global shortcut is taken from every
        // other program on the machine while it is held, so these are only
        // bound while the overlay is switched on.
        SettingsCard(
          child: Text(
            prefs.enabled
                ? 'These are held system-wide while the overlay is switched '
                      'on, and released when it is off.'
                : 'These are not bound while the overlay is switched off, so '
                      'they stay available to everything else on the machine.',
            style: context.text.subtitle,
          ),
        ),
        const SizedBox(height: 8),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OverlayHotkeyRow(
                action: HotkeyAction.overlayToggle,
                description:
                    'Pushes the HUD out of the way without switching the '
                    'feature off, so the same chord brings it back.',
              ),
              const SettingsDivider(),
              _OverlayHotkeyRow(
                action: HotkeyAction.overlayEdit,
                description:
                    'Lets you drag the overlay into place. The game loses '
                    'the foreground while you do, which is unavoidable — a '
                    'window that cannot be clicked cannot be arranged.',
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
              onChanged: (next, {bool write = true}) {
                notifier.updateLayout(next, write: write);
                // On release, not on every frame of the drag — `write` is
                // false while a slider is being dragged, which is the same
                // split the write itself uses.
                //
                // Handed the layout rather than merely poked, because the
                // write above only reaches the controller a rebuild later:
                // asking it to re-evaluate here would compute the old value,
                // and the new one would not land until something else caused
                // a reconcile.
                if (write) {
                  ref.read(overlayControllerProvider).applyLayoutNow(next);
                }
              },
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
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: context.text.sized(12),
                  ),
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
              icon: Icon(
                Icons.delete_outline,
                color: colors.voiceControlDanger,
              ),
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
          label: 'Visible when talking',
          value: layout.activeOpacity,
          min: 0,
          max: 1,
          // Zero is allowed and is not a mistake: "never show me anything"
          // with the overlay still switched on is a coherent thing to want
          // while it is set up, or while a particular game needs the screen.
          format: (value) =>
              value == 0 ? 'Nothing at all' : '${(value * 100).round()}%',
          onChanged: (value) =>
              onChanged(layout.copyWith(activeOpacity: value), write: false),
          onCommit: (value) => onChanged(layout.copyWith(activeOpacity: value)),
        ),
        _Slider(
          label: 'Visible when silent',
          value: layout.idleOpacity,
          min: 0,
          max: 1,
          // "Nothing at all", not "Invisible", because that is now literally
          // what happens. The fade is applied to the whole window rather than
          // to the individual entries — a layered window has no per-pixel
          // transparency to give them — so at zero the overlay does not dim,
          // it disappears, and somebody who switched the feature on and sees
          // an empty screen has no way to tell that from it being broken.
          format: (value) =>
              value == 0 ? 'Nothing at all' : '${(value * 100).round()}%',
          onChanged: (value) =>
              onChanged(layout.copyWith(idleOpacity: value), write: false),
          onCommit: (value) => onChanged(layout.copyWith(idleOpacity: value)),
        ),
        if (layout.activeOpacity == 0 || layout.idleOpacity == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              // Both at zero is the state worth naming loudest: the feature is
              // switched on, the window is up, and nothing will ever be drawn
              // — which from the outside is indistinguishable from it being
              // broken.
              layout.activeOpacity == 0 && layout.idleOpacity == 0
                  ? 'Both are zero, so the overlay will never appear even '
                        'though it is switched on. Raise at least one.'
                  : layout.activeOpacity == 0
                  ? 'At zero the overlay stays hidden even while somebody is '
                        'talking, which is the moment it exists for.'
                  : 'At zero the whole overlay vanishes once "Stay up for" '
                        'has elapsed, and comes back only while somebody is '
                        'talking. Raise it if you expected to see the roster.',
              style: context.text.timestamp.copyWith(
                color: context.colors.warning,
              ),
            ),
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
          // The chord can be unbound now that it lives in the shared store,
          // and "dragging the overlay itself — Not set." is not a sentence.
          switch (ref.watch(hotkeysProvider)[HotkeyAction.overlayEdit]) {
            final chord? =>
              'Position is set by dragging the overlay itself — '
                  '${hotkeyLabel(chord)}.',
            _ =>
              'Position is set by dragging the overlay itself. Bind '
                  '"${HotkeyAction.overlayEdit.label}" under Shortcuts to be '
                  'able to.',
          },
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
          _AssignForeground(
            prefs: prefs,
            executable: controller.foregroundExecutable,
          ),
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
            ref.read(overlayPrefsProvider.notifier).assign(executable, value);
          },
        ),
      ],
    );
  }
}

/// How long the HUD stays up after the last person stops talking.
///
/// The slider is logarithmic, and it has to be: the range runs from a tenth of
/// a second to an hour, which is four decades. Linear, everything under a
/// minute would live in the first pixel.
class _LingerCard extends ConsumerWidget {
  const _LingerCard({required this.linger});

  final Duration linger;

  /// Position on the slider, 0..1, for a duration.
  static double _positionOf(Duration value) {
    final min = math.log(kMinOverlayLinger.inMilliseconds.toDouble());
    final max = math.log(kMaxOverlayLinger.inMilliseconds.toDouble());
    final here = math.log(
      value.inMilliseconds
          .clamp(
            kMinOverlayLinger.inMilliseconds,
            kMaxOverlayLinger.inMilliseconds,
          )
          .toDouble(),
    );
    return ((here - min) / (max - min)).clamp(0.0, 1.0);
  }

  /// The inverse, rounded to something a person would have chosen.
  static Duration _durationAt(double position) {
    final min = math.log(kMinOverlayLinger.inMilliseconds.toDouble());
    final max = math.log(kMaxOverlayLinger.inMilliseconds.toDouble());
    final ms = math.exp(min + (max - min) * position.clamp(0.0, 1.0));

    // Snapped so the readout says "5 s" rather than "4.87 s". The step grows
    // with the value, which is what makes the whole range usable from one
    // slider.
    final rounded = switch (ms) {
      < 1000 => (ms / 100).round() * 100,
      < 10000 => (ms / 500).round() * 500,
      < 60000 => (ms / 1000).round() * 1000,
      < 600000 => (ms / 15000).round() * 15000,
      _ => (ms / 60000).round() * 60000,
    };

    return Duration(
      milliseconds: rounded.clamp(
        kMinOverlayLinger.inMilliseconds,
        kMaxOverlayLinger.inMilliseconds,
      ),
    );
  }

  static String _format(Duration value) {
    if (value.inMilliseconds < 1000) return '${value.inMilliseconds} ms';
    if (value.inSeconds < 60) {
      final seconds = value.inMilliseconds / 1000;
      return seconds == seconds.roundToDouble()
          ? '${seconds.round()} s'
          : '${seconds.toStringAsFixed(1)} s';
    }
    if (value.inMinutes < 60) return '${value.inMinutes} min';
    return '1 hour';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(overlayPrefsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          title: 'Stay up for',
          subtitle:
              'After the last person stops talking, the HUD holds for '
              '${_format(linger)} before fading to "Visible when silent".',
          hint:
              'The overlay fades as a whole rather than per person — a '
              'layered window has no per-pixel transparency to give the '
              'individual entries. Holding it up for a moment is what stops '
              'an ordinary back-and-forth conversation reading as flicker.',
        ),
        Slider(
          value: _positionOf(linger),
          label: _format(linger),
          // Dragging redraws live; only the release is written to disk.
          onChanged: (value) =>
              notifier.setLinger(_durationAt(value), commit: false),
          onChangeEnd: (value) => notifier.setLinger(_durationAt(value)),
        ),
        Row(
          children: [
            Text(_format(kMinOverlayLinger), style: context.text.timestamp),
            const Spacer(),
            if (linger != kDefaultOverlayLinger)
              TextButton(
                onPressed: () => notifier.setLinger(kDefaultOverlayLinger),
                child: const Text('Reset'),
              ),
            const Spacer(),
            Text(_format(kMaxOverlayLinger), style: context.text.timestamp),
          ],
        ),
      ],
    );
  }
}

/// One of the overlay's two chords, bound through the shared registry.
///
/// A widget rather than two inline `HotkeyRow`s because each needs to watch
/// the bindings and the binder to report a refused or doubly-bound chord, and
/// `OverlayPane.build` already watches enough.
class _OverlayHotkeyRow extends ConsumerWidget {
  const _OverlayHotkeyRow({required this.action, required this.description});

  final HotkeyAction action;

  /// What the chord does, shown when there is nothing wrong with it.
  final String description;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = ref.watch(hotkeysProvider);
    final binder = ref.watch(hotkeyBinderProvider);

    return ValueListenableBuilder(
      valueListenable: binder.rejected,
      builder: (context, rejected, _) => HotkeyRow(
        key: Key('hotkey_${action.name}'),
        label: action.label,
        hint: description,
        problem: hotkeyProblem(bindings, rejected, action),
        hotkey: bindings[action] ?? const Hotkey.none(),
        onChanged: (hotkey) => ref
            .read(hotkeysProvider.notifier)
            .setBinding(action, hotkey.isBound ? hotkey : null),
      ),
    );
  }
}
