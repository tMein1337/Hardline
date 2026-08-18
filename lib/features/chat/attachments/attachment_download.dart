// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:matrix/matrix.dart';

import 'attachment_picker_source.dart';
import 'safe_filename.dart';

/// Saves an attachment to a location the user chooses.
///
/// Returns false when the save dialog was cancelled, which is not an error and
/// should leave the UI unchanged. Any real failure is thrown for the caller to
/// render through `describeAttachmentError`.
///
/// The dialog comes **before** the download on purpose: cancelling is common,
/// and it must not have cost a 50 MB transfer first. The trade-off is that the
/// wait happens after the click rather than before it.
Future<bool> saveAttachment(Event event) async {
  // Both of these are written by the sender, so neither is a filename until
  // `safeFilename` has had a look at it. See that library for what an
  // unsanitised one can do to a save dialog.
  final suggested = safeFilename(
    event.content.tryGet<String>('filename') ??
        event.content.tryGet<String>('body') ??
        kFallbackFilename,
  );

  final path = await chooseSaveLocation(suggestedName: suggested);
  if (path == null) return false;

  // Handles the encrypted and unencrypted cases identically, and reuses the
  // SDK's file cache so saving something already shown inline is free.
  final file = await event.downloadAndDecryptAttachment();
  await File(path).writeAsBytes(file.bytes, flush: true);
  return true;
}
