// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../activity/widgets/user_context_menu.dart';
import '../message_links.dart';
import 'message_link_opener.dart';

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
  const LinkifiedText({
    super.key,
    required this.text,
    required this.style,
    this.mentions = const {},
    this.suffix,
    this.suffixStyle,
  });

  final String text;

  /// Small text after the body that is not part of it, such as "(edited)".
  final String? suffix;
  final TextStyle? suffixStyle;

  /// Applied to the whole body; links add a colour and an underline on top.
  final TextStyle style;

  /// User id to display name, for the people this message actually mentions.
  ///
  /// From `m.mentions.user_ids`, never inferred from the text — see
  /// `splitMentions`. Empty for the overwhelming majority of messages.
  final Map<String, String> mentions;

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
    if (oldWidget.text != widget.text ||
        !mapEquals(oldWidget.mentions, widget.mentions)) {
      _parse();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _parse() {
    _disposeRecognizers();
    _spans = splitMentions(splitBodyLinks(widget.text), widget.mentions);
    for (final span in _spans) {
      final target = span.target;
      if (target != null) {
        _recognizers.add(TapGestureRecognizer()..onTap = () => _open(target));
        continue;
      }
      final userId = span.userId;
      if (userId != null) {
        _recognizers.add(
          TapGestureRecognizer()..onTap = () => _openProfile(userId),
        );
      }
    }
  }

  void _openProfile(String userId) {
    UserContextMenu.show(
      context,
      userId: userId,
      displayName: widget.mentions[userId] ?? userId,
    );
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri target) => openMessageLink(context, ref, target);

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    final linkStyle = widget.style.copyWith(
      color: accent,
      decoration: TextDecoration.underline,
      decorationColor: accent,
    );

    // The orange outline the issue asks for. A mention of *somebody else* has
    // to be visible as a mention — the accent background and border say "this
    // names a person" without claiming it names you, which is what the tile's
    // own highlight is already for.
    final mentionStyle = widget.style.copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
    );

    final children = <InlineSpan>[];
    var recognizer = 0;
    for (final span in _spans) {
      if (span.isLink) {
        children.add(
          TextSpan(
            text: span.text,
            style: linkStyle,
            recognizer: _recognizers[recognizer++],
            mouseCursor: SystemMouseCursors.click,
          ),
        );
        continue;
      }
      if (span.isMention) {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _MentionPill(
              label: span.text,
              style: mentionStyle,
              recognizer: _recognizers[recognizer++],
            ),
          ),
        );
        continue;
      }
      children.add(TextSpan(text: span.text));
    }
    final suffix = widget.suffix;
    if (suffix != null) {
      children.add(TextSpan(text: suffix, style: widget.suffixStyle));
    }

    return SelectableText.rich(
      TextSpan(style: widget.style, children: children),
    );
  }
}

/// A mention, drawn as a pill.
///
/// A `WidgetSpan` rather than a styled `TextSpan` because a background with
/// padding and a border is not something a text style can express. The cost is
/// that a pill does not participate in text selection — copying a message
/// leaves a gap where the name was — which is why the plain body is still what
/// gets sent and what every other client falls back to.
class _MentionPill extends StatelessWidget {
  const _MentionPill({
    required this.label,
    required this.style,
    required this.recognizer,
  });

  final String label;
  final TextStyle style;
  final TapGestureRecognizer recognizer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: recognizer.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.accent.withValues(alpha: 0.55)),
          ),
          child: Text(label, style: style),
        ),
      ),
    );
  }
}
