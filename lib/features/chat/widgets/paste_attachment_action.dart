import 'dart:async';

import 'package:flutter/material.dart';

import '../attachments/attachment_clipboard_source.dart';
import '../attachments/attachment_staging.dart';

/// Intercepts paste so a copied image or file is attached instead of pasted as
/// text.
///
/// Overriding [PasteTextIntent] rather than watching for Ctrl+V in the
/// composer's `Focus.onKeyEvent`, for three reasons — the first of which is
/// fatal:
///
/// 1. A key handler must answer **synchronously**, but reading the clipboard is
///    async. Returning `ignored` lets the text land before we know there was an
///    image; returning `handled` breaks ordinary text paste. There is no third
///    answer.
/// 2. A key handler sees Ctrl+V only — not the right-click menu's *Paste*, not
///    Shift+Insert. Both of those dispatch [PasteTextIntent].
/// 3. It would have to reimplement selection replacement, `\r\n` handling and
///    undo history, all of which the framework already gets right.
///
/// `EditableText` registers its own paste through `Action.overridable`, which
/// exists precisely so an ancestor `Actions` wins and still receives a
/// [callingAction] pointing at the default. This is the supported path.
///
/// The cost, which is worth knowing: ordinary text paste now waits on one
/// clipboard round trip (tens of milliseconds). If the user types in that
/// window the text lands at the *then* current caret.
class PasteAttachmentAction extends Action<PasteTextIntent> {
  PasteAttachmentAction({required this.onAttachments});

  /// Returns true when it consumed the clipboard contents, false to let the
  /// normal text paste happen instead.
  final Future<bool> Function(IncomingAttachments) onAttachments;

  bool _busy = false;

  @override
  Object? invoke(PasteTextIntent intent) {
    // callingAction is only valid for the duration of this synchronous call —
    // the overridable wrapper clears it on the way out — so it has to be
    // captured here and used after the await, not read again later.
    final fallback = callingAction;

    if (!_busy) unawaited(_run(intent, fallback));
    return null;
  }

  Future<void> _run(
    PasteTextIntent intent,
    Action<PasteTextIntent>? fallback,
  ) async {
    _busy = true;
    try {
      final found = await readClipboardAttachments();
      if (found != null && await onAttachments(found)) return;

      // Nothing attachable. Hand back to EditableText's own paste, which knows
      // how to replace the selection, extend the undo history and dismiss the
      // toolbar.
      fallback?.invoke(intent);
    } catch (error) {
      debugPrint('Could not read the clipboard: $error');
      fallback?.invoke(intent);
    } finally {
      _busy = false;
    }
  }
}
