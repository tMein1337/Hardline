// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../../../theme/theme_context.dart';
import '../screen_sources.dart';

/// What is being shared, chosen here rather than by livekit_client.
///
/// Replaces `lk.ScreenSelectDialog`, which had three problems and every one of
/// them was visible to the user:
///
///  * **It is hard-coded white.** `Container(color: Colors.white)` with
///    `Colors.black87` text, reading nothing from the theme except the Share
///    button's tint. In a dark app it arrives as a rectangle of daylight.
///  * **It filters nothing.** Everything Windows reports as capturable is
///    offered, including shell surfaces like the taskbar overflow window, which
///    cannot usefully be shared and often produce a blank stream.
///  * **It returns only `source.id`.** The window title — the one string a
///    person recognises — is dropped at the door, which is why the sharing list
///    used to identify shares by a capture GUID.
///
/// Upstream also marks it experimental, and the copy in the pub cache carries
/// local edits that a clean `pub get` would erase. So this one is ours.
class ScreenSourcePicker extends StatefulWidget {
  const ScreenSourcePicker({super.key});

  /// The chosen source, or null if the dialog was dismissed.
  static Future<rtc.DesktopCapturerSource?> show(BuildContext context) {
    return showDialog<rtc.DesktopCapturerSource>(
      context: context,
      builder: (_) => const ScreenSourcePicker(),
    );
  }

  @override
  State<ScreenSourcePicker> createState() => _ScreenSourcePickerState();
}

class _ScreenSourcePickerState extends State<ScreenSourcePicker> {
  /// Thumbnails refresh on a timer rather than arriving unprompted, which is
  /// how flutter_webrtc's capturer works. Slow enough not to matter, quick
  /// enough that a window you just moved looks right.
  static const _refresh = Duration(seconds: 3);

  static const _tileExtent = 180.0;

  final _sources = <String, rtc.DesktopCapturerSource>{};
  final _subscriptions = <StreamSubscription<dynamic>>[];

  Timer? _timer;
  rtc.SourceType _tab = rtc.SourceType.Screen;
  String? _selectedId;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());

    final capturer = rtc.desktopCapturer;
    _subscriptions.addAll([
      capturer.onAdded.stream.listen((source) {
        if (mounted) setState(() => _sources[source.id] = source);
      }),
      capturer.onRemoved.stream.listen((source) {
        if (!mounted) return;
        setState(() {
          _sources.remove(source.id);
          if (_selectedId == source.id) _selectedId = null;
        });
      }),
      capturer.onThumbnailChanged.stream.listen((_) {
        if (mounted) setState(() {});
      }),
      capturer.onNameChanged.stream.listen((_) {
        if (mounted) setState(() {});
      }),
    ]);

    _timer = Timer.periodic(_refresh, (_) async {
      try {
        await rtc.desktopCapturer.updateSources(
          types: [rtc.SourceType.Screen, rtc.SourceType.Window],
        );
      } catch (_) {
        // A refresh that failed is not worth interrupting the dialog over.
        // Whatever is already on screen is still choosable.
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sources = await rtc.desktopCapturer.getSources(
        types: [rtc.SourceType.Screen, rtc.SourceType.Window],
        thumbnailSize: rtc.ThumbnailSize(320, 180),
      );
      if (!mounted) return;
      setState(() {
        _sources
          ..clear()
          ..addEntries([for (final source in sources) MapEntry(source.id, source)]);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// The sources for the open tab, filtered and ordered.
  List<rtc.DesktopCapturerSource> get _visible {
    final matching = [
      for (final source in _sources.values)
        if (source.type == _tab &&
            isShareableSource(
              name: source.name,
              isWindow: source.type == rtc.SourceType.Window,
              thumbnailWidth: source.thumbnailSize.width,
              thumbnailHeight: source.thumbnailSize.height,
            ))
          source,
    ];
    // A stable order, so a list that refreshes every three seconds does not
    // reshuffle under somebody's pointer as they reach for a tile.
    matching.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return matching;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = _selectedId;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Share your screen', style: context.text.title),
      content: SizedBox(
        width: 640,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Tabs(
              selected: _tab,
              onChanged: (tab) => setState(() {
                _tab = tab;
                _selectedId = null;
              }),
            ),
            const SizedBox(height: 12),
            Expanded(child: _body(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected == null
              ? null
              : () => Navigator.of(context).pop(_sources[selected]),
          child: const Text('Share'),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error case final error?) {
      return Center(
        child: Text(
          'Could not read what is on screen.\n$error',
          style: context.text.subtitle,
          textAlign: TextAlign.center,
        ),
      );
    }

    final sources = _visible;
    if (sources.isEmpty) {
      return Center(
        child: Text(
          _tab == rtc.SourceType.Screen
              ? 'No screen found.'
              : 'No window is open that can be shared.',
          style: context.text.subtitle,
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _tileExtent,
        childAspectRatio: 0.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        return _SourceTile(
          source: source,
          selected: source.id == _selectedId,
          onTap: () => setState(() => _selectedId = source.id),
          // Double-click shares immediately, which is what people try first.
          onConfirm: () => Navigator.of(context).pop(source),
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onChanged});

  final rtc.SourceType selected;
  final ValueChanged<rtc.SourceType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in const [
          (rtc.SourceType.Screen, 'Screens'),
          (rtc.SourceType.Window, 'Windows'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Tab(
              label: entry.$2,
              selected: entry.$1 == selected,
              onTap: () => onChanged(entry.$1),
            ),
          ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.inputBackground,
          borderRadius: BorderRadius.circular(context.metrics.rowRadius * 2),
          border: Border.all(
            color: selected ? colors.accent : colors.inputBorder,
          ),
        ),
        child: Text(
          label,
          style: context.text.buttonLabel.copyWith(
            color: selected ? colors.textOnAccent : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
    required this.onConfirm,
  });

  final rtc.DesktopCapturerSource source;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final thumbnail = source.thumbnail;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onConfirm,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.videoTileBackground,
                borderRadius: BorderRadius.circular(context.metrics.rowRadius),
                border: Border.all(
                  color: selected ? colors.accent : colors.inputBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: thumbnail == null
                    ? Center(
                        child: Icon(
                          source.type == rtc.SourceType.Screen
                              ? Icons.monitor
                              : Icons.web_asset,
                          color: colors.videoTilePlaceholder,
                        ),
                      )
                    : Image.memory(
                        thumbnail,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            source.name,
            style: context.text.timestamp.copyWith(
              color: selected ? colors.accent : colors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
