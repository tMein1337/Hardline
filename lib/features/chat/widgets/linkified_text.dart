// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../core/util/open_link.dart';
import '../../../theme/theme_context.dart';
import '../../activity/activity_navigation.dart';
import '../message_links.dart';
import 'link_confirmation.dart';

/// Message text whose links can be clicked, and which is still selectable.
///
/// `SelectableText.rich` rather than `Text.rich` inside a `SelectionArea`,
/// because selecting one message is the older and more common thing to want and
/// it must not be traded away for a click. The two do coexist:
/// `RenderEditable.hitTestChildren` resolves the span under the pointer and
/// hands the event to that span's recognizer, while a *drag* still wins the
/// gesture arena and selects — so pressing a link and dragging highlights text
/// rather than opening anything, which is the behaviour people expect.
class LinkifiedText extends ConsumerStatefulWidget {
  const LinkifiedText({super.key, required this.text, required this.style});

  final String text;

  /// Applied to the whole body; links add a colour and an underline on top.
  final TextStyle style;

  @override
  ConsumerState<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends ConsumerState<LinkifiedText> {
  List<BodySpan> _spans = const <BodySpan>[];

  /// One per link, in the order the links appear. Recognizers own resources and
  /// have to be disposed, which is the only reason this is a `State` at all.
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only the text decides the spans. Rebuilding them for a theme change would
    // dispose a recognizer mid-press, which is a click that silently does
    // nothing — and recolouring is exactly what happens while a theme slider is
    // being dragged.
    if (oldWidget.text != widget.text) _parse();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _parse() {
    _disposeRecognizers();
    _spans = splitBodyLinks(widget.text);
    for (final span in _spans) {
      final target = span.target;
      if (target == null) continue;
      _recognizers.add(TapGestureRecognizer()..onTap = () => _open(target));
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri target) async {
    // A permalink that resolves to a room in this app never leaves it, so
    // there is nothing to confirm. The step exists for handing an address
    // somebody else wrote to the browser, which is a different act.
    final matrixTo = parseMatrixTo(target);
    if (matrixTo != null && _openHere(matrixTo)) return;

    if (!await confirmOpenLink(context, ref, target)) return;
    if (!mounted) return;
    await openExternalUrl(context, target);
  }

  /// Opens a `matrix.to` link inside the app, and reports whether it could.
  ///
  /// A permalink to a room this account is already in has no business going out
  /// to a web page that exists only to send the reader back again. A room we are
  /// *not* in, or a link to a person, is a different matter: matrix.to's page
  /// offers to join or to start a chat, which is more than this app has to show
  /// for one, so those are left to the browser.
  bool _openHere(MatrixToTarget target) {
    final identifier = target.identifier;
    final client = ref.read(clientProvider);
    final room = identifier.startsWith('#')
        ? client.getRoomByAlias(identifier)
        : client.getRoomById(identifier);
    if (room == null) return false;

    final eventId = target.eventId;
    if (eventId == null) {
      openRoom(ref, room.id);
    } else {
      jumpToMessage(ref, room.id, eventId);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    final linkStyle = widget.style.copyWith(
      color: accent,
      decoration: TextDecoration.underline,
      decorationColor: accent,
    );

    final children = <TextSpan>[];
    var link = 0;
    for (final span in _spans) {
      children.add(
        span.isLink
            ? TextSpan(
                text: span.text,
                style: linkStyle,
                recognizer: _recognizers[link++],
                mouseCursor: SystemMouseCursors.click,
              )
            : TextSpan(text: span.text),
      );
    }

    return SelectableText.rich(
      TextSpan(style: widget.style, children: children),
    );
  }
}
