import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/app_error_view.dart';
import '../../common/app_splash.dart';
import '../message_item.dart';
import '../timeline_controller.dart';
import '../timeline_provider.dart';
import 'date_separator.dart';
import 'history_loader.dart';
import 'message_tile.dart';
import 'system_event_tile.dart';

/// How close to the top edge triggers loading the next page.
const _paginationThreshold = 400.0;

class MessageList extends ConsumerStatefulWidget {
  const MessageList({super.key, required this.roomId, required this.roomName});

  final String roomId;
  final String roomName;

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybePaginate);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybePaginate);
    _scroll.dispose();
    super.dispose();
  }

  void _maybePaginate() {
    if (!_scroll.hasClients) return;
    // reverse: true means scrolling up towards older messages *increases*
    // pixels, so maxScrollExtent is the top of history.
    final distanceToTop = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (distanceToTop > _paginationThreshold) return;

    unawaited(ref.read(timelineControllerProvider(widget.roomId)).loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(timelineControllerProvider(widget.roomId));

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
              return switch (item) {
                MessageItem() => MessageTile(
                  key: ValueKey(item.key),
                  event: item.event,
                  showHeader: item.showHeader,
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
