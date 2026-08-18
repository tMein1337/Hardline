// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../common/app_error_view.dart';
import '../../common/app_splash.dart';
import '../highlight_provider.dart';
import '../message_item.dart';
import '../read_receipt_sender.dart';
import '../timeline_controller.dart';
import '../timeline_provider.dart';
import 'date_separator.dart';
import 'history_loader.dart';
import 'message_tile.dart';
import 'system_event_tile.dart';

/// How close to the top edge triggers loading the next page.
const _paginationThreshold = 400.0;

/// How long a jumped-to message stays washed before fading back.
const _highlightDuration = Duration(milliseconds: 2500);

/// Pages pulled while hunting for a message that is not loaded yet.
///
/// The activity summary only ever points at something inside its "recent"
/// window, so the target is almost always on the first page already. This is
/// the ceiling for the case where it is not, so a jump to something the room
/// has long since scrolled past stops rather than paginating to the start of
/// history.
const _maxRevealPages = 4;

/// Frames to wait for the target row to be laid out before giving up.
const _maxRevealFrames = 3;

class MessageList extends ConsumerStatefulWidget {
  const MessageList({super.key, required this.roomId, required this.roomName});

  final String roomId;
  final String roomName;

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList> {
  final _scroll = ScrollController();

  /// Attached to the highlighted row only, so `ensureVisible` has something to
  /// aim at. One key rather than one per row: only one message is ever the
  /// target, and a map of keys would have to be rebuilt with the list.
  final _highlightKey = GlobalKey();

  String? _highlightedEventId;
  Timer? _highlightTimer;

  late final TimelineController _controller;
  late final ReadReceiptSender _receipts;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);

    // Stable for the life of this widget: both are keyed by room id, so a room
    // switch replaces the whole state object rather than repointing it.
    _controller = ref.read(timelineControllerProvider(widget.roomId));
    _receipts = ReadReceiptSender(
      client: ref.read(clientProvider),
      roomId: widget.roomId,
    );
    // The controller notifies on every timeline change, which is exactly when
    // "the newest event" can have moved.
    _controller.addListener(_onTimelineChanged);
    _markReadIfLooking();

    // A request filed *before* this list existed — which is what clicking an
    // activity row in another room does, since selecting the room rebuilds the
    // chat panel — is already sitting in the provider when we mount.
    final pending = ref.read(highlightedEventProvider);
    if (pending != null && pending.roomId == widget.roomId) {
      unawaited(_reveal(pending.eventId));
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _controller.removeListener(_onTimelineChanged);
    _receipts.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    _maybePaginate();
    // Scrolling back down to the newest end is the other way somebody reads
    // what arrived while they were up in history.
    _markReadIfLooking();
  }

  void _onTimelineChanged() {
    if (mounted) _markReadIfLooking();
  }

  /// Tells the receipt sender what is newest, and whether it is being looked at.
  void _markReadIfLooking() {
    if (_controller.status != TimelineStatus.ready) return;
    _receipts.onNewest(
      _controller.newestSyncedEventId,
      // Before the first layout there is no scroll position, and the list
      // starts pinned to the newest end — so "no clients yet" is at the bottom.
      atBottom: !_scroll.hasClients || isAtNewestEnd(_scroll.position),
    );
  }

  void _maybePaginate() {
    if (!_scroll.hasClients) return;
    // reverse: true means scrolling up towards older messages *increases*
    // pixels, so maxScrollExtent is the top of history.
    final distanceToTop = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (distanceToTop > _paginationThreshold) return;

    unawaited(_controller.loadMore());
  }

  /// Scrolls to [eventId] and marks it.
  ///
  /// The list is a `ListView.builder` with no fixed extent, so there is no
  /// offset to scroll to directly. The two-step below is what avoids pulling in
  /// a positioned-list package for one screen: aim with the delegate's own
  /// extent estimate, then let `ensureVisible` correct it once the real row has
  /// been laid out.
  Future<void> _reveal(String eventId) async {
    final controller = _controller;

    // Jumping from another room mounts this list and the timeline at the same
    // moment, so on arrival there is usually nothing loaded yet. Hunting now
    // would find no event, see `canLoadMore` false because there is no timeline
    // to page, and give up before the room had opened.
    await _awaitTimeline(controller);
    if (!mounted || controller.status != TimelineStatus.ready) return;

    // The message may be older than the first page. Pull history until it turns
    // up, or until there is no more to pull.
    var index = controller.indexOfEvent(eventId);
    for (var page = 0; index < 0 && page < _maxRevealPages; page++) {
      if (!controller.canLoadMore) break;
      await controller.loadMore();
      if (!mounted) return;
      index = controller.indexOfEvent(eventId);
    }

    // Mark it even when it could not be found: the wash is what identifies the
    // message once the user scrolls to it themselves, and marking nothing would
    // make a failed jump indistinguishable from a jump to the wrong place.
    _setHighlight(eventId);
    ref.read(highlightedEventProvider.notifier).clear();
    if (index < 0) return;

    // Aim. `maxScrollExtent` on a builder-backed list is extrapolated from the
    // children built so far, which is exactly the average-row estimate wanted
    // here — approximate, and corrected in the next step.
    if (_scroll.hasClients && controller.items.isNotEmpty) {
      final estimate =
          _scroll.position.maxScrollExtent * index / controller.items.length;
      _scroll.jumpTo(estimate.clamp(0.0, _scroll.position.maxScrollExtent));
    }

    // Correct. The row is only laid out once the aimed-at region has been
    // built, which is a frame or two away.
    for (var frame = 0; frame < _maxRevealFrames; frame++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final target = _highlightKey.currentContext;
      if (target == null || !target.mounted) continue;
      await Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      return;
    }
  }

  /// Waits for the timeline's first page, or gives up.
  ///
  /// Listener-driven rather than frame-polled: opening a cold room can take a
  /// second or more, and spinning frames to find out would burn a whole core to
  /// learn nothing. The timeout is the escape hatch for a room that never
  /// resolves, where a jump that quietly does nothing beats one that hangs.
  Future<void> _awaitTimeline(TimelineController controller) async {
    if (controller.status != TimelineStatus.loading) return;

    final ready = Completer<void>();
    void check() {
      if (controller.status != TimelineStatus.loading && !ready.isCompleted) {
        ready.complete();
      }
    }

    controller.addListener(check);
    try {
      await ready.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
    } finally {
      // Safe even if the controller was disposed while we waited — which is
      // what a second room switch does. Only addListener asserts.
      controller.removeListener(check);
    }
  }

  void _setHighlight(String eventId) {
    _highlightTimer?.cancel();
    setState(() => _highlightedEventId = eventId);
    _highlightTimer = Timer(_highlightDuration, () {
      if (mounted) setState(() => _highlightedEventId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(timelineControllerProvider(widget.roomId));

    // Requests filed while this room is already open. The one filed before the
    // list existed is picked up in initState instead.
    ref.listen(highlightedEventProvider, (_, request) {
      if (request == null || request.roomId != widget.roomId) return;
      unawaited(_reveal(request.eventId));
    });

    // ListenableBuilder rather than provider state: the timeline changes far
    // too often to round-trip through value snapshots, and this scopes the
    // rebuild to the list alone — the header and composer are untouched.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.status) {
          case TimelineStatus.loading:
            return const AppSplash();
          case TimelineStatus.error:
            return AppErrorView(
              title: 'Could not open this room',
              error: controller.error ?? 'Unknown error',
            );
          case TimelineStatus.ready:
            break;
        }

        final items = controller.items;

        return Scrollbar(
          controller: _scroll,
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.only(bottom: 16),
            // One extra row at the end (visually the top) for the loader or
            // the start-of-history block.
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == items.length) {
                return controller.canLoadMore
                    ? const HistoryLoader()
                    : ChannelWelcome(roomName: widget.roomName);
              }

              final item = items[index];
              final highlighted = item.key == _highlightedEventId;

              return switch (item) {
                MessageItem() => MessageTile(
                  key: ValueKey(item.key),
                  event: item.event,
                  showHeader: item.showHeader,
                  highlighted: highlighted,
                  // The scroll target, and only on the one row that is it.
                  anchorKey: highlighted ? _highlightKey : null,
                ),
                SystemItem() => SystemEventTile(
                  key: ValueKey(item.key),
                  event: item.event,
                ),
                DateSeparatorItem() => DateSeparator(
                  key: ValueKey(item.key),
                  date: item.date,
                ),
              };
            },
          ),
        );
      },
    );
  }
}
