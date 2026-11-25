// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;

import '../../../core/matrix/avatar_uri_provider.dart';
import '../../../theme/color_slots.dart';
import '../../../theme/theme_context.dart';
import '../../../theme/typography.dart';
import '../../activity/widgets/user_context_menu.dart';
import '../matrix_html.dart';
import '../message_links.dart';
import 'message_link_opener.dart';

/// A message's `formatted_body`, drawn.
///
/// Covers everything the Matrix HTML subset can say: headings, emphasis,
/// underline and strikethrough, inline code and code blocks, quotes, ordered
/// and unordered lists, tables, rules, links, mentions, coloured text,
/// spoilers, super- and subscript, collapsible details and inline images
/// from the homeserver. The HTML goes through `matrix_html.dart` first, so a
/// tag outside the subset never reaches this widget.
///
/// Every link — unlike in a plain-text message, where a link's label *is* its
/// address — can say one thing and point at another, which is why all of them
/// go through [openMessageLink] and its confirmation step showing the real
/// target.
class FormattedBody extends ConsumerStatefulWidget {
  const FormattedBody({
    super.key,
    required this.html,
    required this.style,
    this.mentions = const {},
    this.suffix,
    this.suffixStyle,
  });

  final String html;
  final TextStyle style;

  /// User id to display name, for the people `m.mentions` names. A link to
  /// one of them is drawn as a mention under the name this client knows.
  final Map<String, String> mentions;

  final String? suffix;
  final TextStyle? suffixStyle;

  @override
  ConsumerState<FormattedBody> createState() => _FormattedBodyState();
}

class _FormattedBodyState extends ConsumerState<FormattedBody> {
  late dom.DocumentFragment _fragment;

  /// Recognizers by position in the document, reused across rebuilds so a
  /// theme change mid-press does not dispose the one being pressed.
  final _recognizers = <TapGestureRecognizer>[];

  /// Spoilers clicked open, by position in the document.
  final _revealed = <int>{};

  @override
  void initState() {
    super.initState();
    _fragment = parseMatrixHtml(widget.html);
  }

  @override
  void didUpdateWidget(FormattedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _fragment = parseMatrixHtml(widget.html);
      _disposeRecognizers();
      _revealed.clear();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _Renderer(
      context: context,
      colors: context.colors,
      base: widget.style,
      mentions: widget.mentions,
      recognizer: (index, onTap) {
        while (_recognizers.length <= index) {
          _recognizers.add(TapGestureRecognizer());
        }
        return _recognizers[index]..onTap = onTap;
      },
      openLink: (uri) => openMessageLink(context, ref, uri),
      openProfile: (userId, name) =>
          UserContextMenu.show(context, userId: userId, displayName: name),
      isRevealed: _revealed.contains,
      reveal: (index) => setState(() => _revealed.add(index)),
    );

    final blocks = renderer.blocks(_fragment.nodes, widget.style, 0);
    final suffix = widget.suffix;
    if (suffix != null) {
      blocks.add(Text(suffix.trim(), style: widget.suffixStyle));
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: blocks,
      ),
    );
  }
}

/// Elements that start a block of their own.
const _blockTags = {
  'p', 'div', 'blockquote', 'pre', 'ul', 'ol', 'li', 'table', 'h1', 'h2', //
  'h3', 'h4', 'h5', 'h6', 'hr', 'details', 'summary', 'caption',
};

const _headingScale = {
  'h1': 1.6,
  'h2': 1.4,
  'h3': 1.25,
  'h4': 1.1,
  'h5': 1.0,
  'h6': 0.9,
};

/// Walks a sanitized fragment and builds widgets and spans from it.
///
/// One instance per build. Link and spoiler indexes are handed out in
/// document order, which is what lets the state keep recognizers and revealed
/// spoilers stable across rebuilds of the same HTML.
class _Renderer {
  _Renderer({
    required this.context,
    required this.colors,
    required this.base,
    required this.mentions,
    required this.recognizer,
    required this.openLink,
    required this.openProfile,
    required this.isRevealed,
    required this.reveal,
  });

  final BuildContext context;
  final AppPalette colors;
  final TextStyle base;
  final Map<String, String> mentions;
  final TapGestureRecognizer Function(int index, VoidCallback onTap) recognizer;
  final void Function(Uri) openLink;
  final void Function(String userId, String name) openProfile;
  final bool Function(int) isRevealed;
  final void Function(int) reveal;

  int _nextRecognizer = 0;
  int _nextSpoiler = 0;

  TextStyle get _mono => base.copyWith(
    fontFamily: AppTypography.monoFamily,
    fontFamilyFallback: AppTypography.monoFamilyFallback,
    fontSize: (base.fontSize ?? 15) * 0.92,
  );

  // ---------------------------------------------------------------------------
  // Blocks
  // ---------------------------------------------------------------------------

  List<Widget> blocks(List<dom.Node> nodes, TextStyle style, int listDepth) {
    final out = <Widget>[];
    var run = <dom.Node>[];

    void flush() {
      final spans = <InlineSpan>[
        for (final node in run) ...inline(node, style),
      ];
      run = [];
      if (_isBlank(spans)) return;
      out.add(Text.rich(TextSpan(style: style, children: spans)));
    }

    for (final node in nodes) {
      if (node is dom.Element && _blockTags.contains(node.localName)) {
        flush();
        final block = _block(node, style, listDepth);
        if (block != null) out.add(block);
      } else {
        run.add(node);
      }
    }
    flush();
    return out;
  }

  Widget? _block(dom.Element element, TextStyle style, int listDepth) {
    final tag = element.localName!;
    switch (tag) {
      case 'p' || 'div' || 'li' || 'caption':
        return _column(blocks(element.nodes, style, listDepth));
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final heading = style.copyWith(
          fontSize: (style.fontSize ?? 15) * _headingScale[tag]!,
          fontWeight: FontWeight.w700,
          color: colors.textHeader,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _column(blocks(element.nodes, heading, listDepth)),
        );
      case 'blockquote':
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: colors.dividerStrong, width: 3),
            ),
          ),
          child: _column(
            blocks(
              element.nodes,
              style.copyWith(color: colors.textMuted),
              listDepth,
            ),
          ),
        );
      case 'pre':
        return _codeBlock(element);
      case 'ul' || 'ol':
        return _list(element, style, listDepth);
      case 'table':
        return _table(element, style);
      case 'hr':
        return Divider(height: 9, thickness: 1, color: colors.divider);
      case 'details':
        return _Details(
          summary: [
            for (final child in element.children)
              if (child.localName == 'summary') ...inline(child, style),
          ],
          style: style,
          body: _column(
            blocks(
              [
                for (final child in element.nodes)
                  if (!(child is dom.Element && child.localName == 'summary'))
                    child,
              ],
              style,
              listDepth,
            ),
          ),
        );
      case 'summary':
        // Outside a <details>: just a line.
        return _column(blocks(element.nodes, style, listDepth));
    }
    return null;
  }

  Widget _column(List<Widget> children) => children.length == 1
      ? children.single
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: children,
        );

  Widget _codeBlock(dom.Element pre) {
    final code = pre.text.replaceFirst(RegExp(r'\n$'), '');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.inputBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(code, style: _mono),
      ),
    );
  }

  Widget _list(dom.Element list, TextStyle style, int depth) {
    final ordered = list.localName == 'ol';
    var number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final bullet = const ['•', '◦', '▪'][depth % 3];

    final items = <Widget>[];
    for (final node in list.nodes) {
      final children = node is dom.Element && node.localName == 'li'
          ? node.nodes
          : [node];
      final content = blocks(children, style, depth + 1);
      if (content.isEmpty) continue;
      items.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: ordered ? 26 : 18,
              child: Text(
                ordered ? '${number++}.' : bullet,
                style: style.copyWith(color: colors.textMuted),
                textAlign: ordered ? TextAlign.right : TextAlign.center,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(child: _column(content)),
          ],
        ),
      );
    }
    return _column(items);
  }

  Widget _table(dom.Element table, TextStyle style) {
    final rows = <List<(dom.Element, bool)>>[];
    void collect(dom.Element parent) {
      for (final child in parent.children) {
        switch (child.localName) {
          case 'thead' || 'tbody' || 'tfoot':
            collect(child);
          case 'tr':
            rows.add([
              for (final cell in child.children)
                if (cell.localName == 'td' || cell.localName == 'th')
                  (cell, cell.localName == 'th'),
            ]);
        }
      }
    }

    collect(table);
    final width = rows.fold<int>(0, (w, r) => r.length > w ? r.length : w);
    if (width == 0) return const SizedBox.shrink();

    final header = style.copyWith(fontWeight: FontWeight.w700);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: colors.divider),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (var i = 0; i < width; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: i < row.length
                        ? _column([
                            ...blocks(
                              row[i].$1.nodes,
                              row[i].$2 ? header : style,
                              0,
                            ),
                            if (row[i].$1.nodes.isEmpty)
                              const SizedBox.shrink(),
                          ])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inline
  // ---------------------------------------------------------------------------

  List<InlineSpan> inline(
    dom.Node node,
    TextStyle style, {
    GestureRecognizer? tap,
    bool literal = false,
  }) {
    if (node is dom.Text) {
      return _text(node.text, style, tap: tap, literal: literal);
    }
    if (node is! dom.Element) return const [];

    final tag = node.localName!;
    List<InlineSpan> children(TextStyle s, {bool literal0 = false}) => [
      for (final child in node.nodes)
        ...inline(child, s, tap: tap, literal: literal || literal0),
    ];

    switch (tag) {
      case 'br':
        return [const TextSpan(text: '\n')];
      case 'b' || 'strong':
        return children(style.copyWith(fontWeight: FontWeight.w700));
      case 'i' || 'em':
        return children(style.copyWith(fontStyle: FontStyle.italic));
      case 'u':
        return children(_decorate(style, TextDecoration.underline));
      case 's' || 'del' || 'strike':
        return children(_decorate(style, TextDecoration.lineThrough));
      case 'code':
        return children(
          _mono.copyWith(
            color: style.color,
            backgroundColor: colors.inputBackground,
          ),
          literal0: true,
        );
      case 'sup' || 'sub':
        return children(
          style.copyWith(
            fontSize: (style.fontSize ?? 15) * 0.75,
            fontFeatures: [
              tag == 'sup'
                  ? const FontFeature.superscripts()
                  : const FontFeature.subscripts(),
            ],
          ),
        );
      case 'font' || 'span':
        if (node.attributes.containsKey('data-mx-spoiler')) {
          return _spoiler(node, style);
        }
        final color = _parseColor(
          node.attributes['data-mx-color'] ?? node.attributes['color'],
        );
        final background = _parseColor(node.attributes['data-mx-bg-color']);
        return children(
          style.copyWith(color: color, backgroundColor: background),
        );
      case 'a':
        return _anchor(node, style);
      case 'img':
        return [_image(node, style)];
    }
    // Anything the sanitizer kept but this does not style: its text.
    return children(style);
  }

  TextStyle _decorate(TextStyle style, TextDecoration decoration) =>
      style.copyWith(
        decoration: TextDecoration.combine([
          if (style.decoration != null) style.decoration!,
          decoration,
        ]),
      );

  /// A text run, with bare addresses made clickable — unless it is already
  /// inside a link, or is code, where an address is just characters.
  List<InlineSpan> _text(
    String text,
    TextStyle style, {
    GestureRecognizer? tap,
    required bool literal,
  }) {
    if (tap != null || literal) {
      return [
        TextSpan(
          text: text,
          style: style,
          recognizer: tap,
          mouseCursor: tap == null ? null : SystemMouseCursors.click,
        ),
      ];
    }
    return [
      for (final span in splitBodyLinks(text))
        if (span.target case final target?)
          TextSpan(
            text: span.text,
            style: _linkStyle(style),
            recognizer: recognizer(_nextRecognizer++, () => openLink(target)),
            mouseCursor: SystemMouseCursors.click,
          )
        else
          TextSpan(text: span.text, style: style),
    ];
  }

  TextStyle _linkStyle(TextStyle style) => style.copyWith(
    color: colors.accent,
    decoration: TextDecoration.underline,
    decorationColor: colors.accent,
  );

  List<InlineSpan> _anchor(dom.Element anchor, TextStyle style) {
    final href = anchor.attributes['href'];
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null) {
      return [for (final c in anchor.nodes) ...inline(c, style)];
    }

    final target = parseMatrixTo(uri);
    if (target != null && target.identifier.startsWith('@')) {
      final userId = target.identifier;
      final name = mentions[userId] ?? anchor.text.replaceFirst('@', '');
      return [
        TextSpan(
          text: '@$name',
          style: style.copyWith(
            color: colors.accent,
            fontWeight: FontWeight.w600,
            backgroundColor: colors.accent.withValues(alpha: 0.12),
          ),
          recognizer: recognizer(
            _nextRecognizer++,
            () => openProfile(userId, name),
          ),
          mouseCursor: SystemMouseCursors.click,
        ),
      ];
    }

    final tap = recognizer(_nextRecognizer++, () => openLink(uri));
    return [
      for (final child in anchor.nodes)
        ...inline(child, _linkStyle(style), tap: tap),
    ];
  }

  List<InlineSpan> _spoiler(dom.Element span, TextStyle style) {
    final index = _nextSpoiler++;
    if (isRevealed(index)) {
      return [
        for (final child in span.nodes)
          ...inline(
            child,
            style.copyWith(
              backgroundColor: colors.textMuted.withValues(alpha: 0.18),
            ),
          ),
      ];
    }
    // Hidden: the text is there, so the line wraps where it will once shown,
    // but drawn in the colour of its own background.
    final hidden = style.copyWith(
      color: colors.textMuted,
      backgroundColor: colors.textMuted,
    );
    final tap = recognizer(_nextRecognizer++, () => reveal(index));
    final reason = span.attributes['data-mx-spoiler'] ?? '';
    return [
      if (reason.isNotEmpty)
        TextSpan(
          text: '($reason) ',
          style: style.copyWith(color: colors.textMuted),
        ),
      TextSpan(
        text: span.text,
        style: hidden,
        recognizer: tap,
        mouseCursor: SystemMouseCursors.click,
      ),
    ];
  }

  InlineSpan _image(dom.Element img, TextStyle style) {
    final src = img.attributes['src'] ?? '';
    final emoticon = img.attributes.containsKey('data-mx-emoticon');
    final lineHeight = (style.fontSize ?? 15) * 1.4;
    final height =
        (double.tryParse(img.attributes['height'] ?? '') ??
                (emoticon ? lineHeight : 128))
            .clamp(8.0, emoticon ? lineHeight * 1.5 : 256.0);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _MxcImage(
        mxc: src,
        size: height,
        label: img.attributes['alt'] ?? img.attributes['title'] ?? '',
      ),
    );
  }

  bool _isBlank(List<InlineSpan> spans) => spans.every(
    (span) =>
        span is TextSpan &&
        (span.text ?? '').trim().isEmpty &&
        (span.children == null || _isBlank(span.children!)),
  );
}

/// `#rrggbb`, the only colour form the spec allows.
Color? _parseColor(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match[1]!, radix: 16));
}

/// An image on the homeserver, as a square thumbnail.
class _MxcImage extends ConsumerWidget {
  const _MxcImage({required this.mxc, required this.size, required this.label});

  final String mxc;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final uri = ref.watch(
      avatarUriProvider(AvatarRequest(mxcUri: mxc, size: pixels)),
    );
    final fallback = Text(label, style: context.text.timestamp);
    return Semantics(
      label: label,
      child: uri.maybeWhen(
        data: (resolved) => resolved == null
            ? fallback
            : Image.network(
                resolved.toString(),
                height: size,
                headers: ref.watch(mediaRequestHeaders),
                errorBuilder: (_, _, _) => fallback,
                gaplessPlayback: true,
              ),
        orElse: () => SizedBox(height: size, width: size),
      ),
    );
  }
}

/// `<details>`: the summary, and the rest behind a click.
class _Details extends StatefulWidget {
  const _Details({
    required this.summary,
    required this.style,
    required this.body,
  });

  final List<InlineSpan> summary;
  final TextStyle style;
  final Widget body;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text.rich(
              TextSpan(
                style: widget.style.copyWith(fontWeight: FontWeight.w600),
                children: [
                  TextSpan(text: _open ? '▾ ' : '▸ '),
                  if (widget.summary.isEmpty)
                    const TextSpan(text: 'Details')
                  else
                    ...widget.summary,
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(padding: const EdgeInsets.only(left: 14), child: widget.body),
      ],
    );
  }
}
