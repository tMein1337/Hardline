// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:matrix/matrix.dart';

import '../../../core/util/byte_format.dart';

/// Converts upload and download failures into something worth showing a user.
///
/// The counterpart to `describeAuthError` in `auth/login_controller.dart`, and
/// for the same reason: one place where exceptions become text, so no widget
/// has to invent its own wording.
///
/// The app has no toast mechanism, so these strings surface in place — under a
/// rejected tray chip, inside a failed timeline tile, or in a save button's
/// tooltip.
String describeAttachmentError(Object error) {
  if (error is FileTooBigMatrixException) {
    return 'That file is too large. This server accepts up to '
        '${formatBytes(error.maxFileSize)}.';
  }
  if (error is FileNoLongerInCacheException) {
    return 'The file is no longer available. Add it again to retry.';
  }
  if (error is MatrixException) {
    switch (error.errcode) {
      case 'M_FORBIDDEN':
        return 'You do not have permission to upload here.';
      case 'M_TOO_LARGE':
        return 'The server rejected this file as too large.';
      case 'M_LIMIT_EXCEEDED':
        return 'Too many uploads. Please wait a moment and try again.';
      default:
        return error.errorMessage;
    }
  }
  if (error is FileSystemException) {
    return 'Could not read that file. It may have been moved or deleted.';
  }
  if (error is SocketException || error is HandshakeException) {
    return "Couldn't reach the server. Check your internet connection.";
  }
  if (error is TimeoutException) {
    return 'The server took too long to respond.';
  }
  return error.toString();
}
