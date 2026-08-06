import 'dart:io';

import 'package:matrix/matrix.dart';

import 'attachment_picker_source.dart';

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
  final suggested =
      event.content.tryGet<String>('filename') ??
      event.content.tryGet<String>('body') ??
      'attachment';

  final path = await chooseSaveLocation(suggestedName: suggested);
  if (path == null) return false;

  // Handles the encrypted and unencrypted cases identically, and reuses the
  // SDK's file cache so saving something already shown inline is free.
  final file = await event.downloadAndDecryptAttachment();
  await File(path).writeAsBytes(file.bytes, flush: true);
  return true;
}
