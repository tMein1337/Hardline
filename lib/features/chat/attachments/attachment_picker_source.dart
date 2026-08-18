// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The `file_selector` adapter.
///
/// One of three source files that import an input package; everything else in
/// the feature speaks plain paths and bytes. Swapping `file_selector` for
/// another picker means rewriting this file and nothing else.
library;

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

/// Opens the system file dialog and returns the chosen paths.
///
/// Empty when the user cancels — a cancel is not an error and should leave the
/// tray untouched.
Future<List<String>> pickAttachmentPaths() async {
  // No acceptedTypeGroups: a chat accepts anything, and an empty list is what
  // shows "All files" rather than an empty dropdown.
  final files = await openFiles();
  return [for (final file in files) file.path];
}

/// Opens the system file dialog filtered to images. Null when the user cancels.
///
/// Used by the avatar picker rather than [pickAttachmentPaths] because a
/// homeserver rejects a non-image avatar after the upload has already happened —
/// filtering here turns that into a dialog that simply does not offer the file.
Future<String?> pickImagePath() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      ),
    ],
  );
  return file?.path;
}

/// Asks where to save a downloaded attachment. Null when the user cancels.
Future<String?> chooseSaveLocation({required String suggestedName}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    // Windows only appends an extension when a type group declares one, so a
    // file saved as "report" becomes "report.pdf" instead of extensionless.
    // Extensions must be bare here — a leading dot makes IFileSaveDialog
    // produce "report..pdf".
    acceptedTypeGroups: _typeGroupFor(suggestedName),
  );
  return location?.path;
}

List<XTypeGroup> _typeGroupFor(String name) {
  final extension = p.extension(name).replaceFirst('.', '');
  if (extension.isEmpty) return const [];

  return [
    XTypeGroup(
      label: extension.toUpperCase(),
      extensions: [extension],
    ),
  ];
}
