// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands [url] to whatever the system uses for the web, and falls back to the
/// clipboard.
///
/// The fallback is the point rather than a nicety. A machine with no browser
/// association, or a desktop portal that declines, must still leave the user
/// able to get at the address; reporting "could not open" and stopping there
/// would be a dead end with the answer already in hand.
///
/// The messenger is resolved *before* the await on purpose. This is called from
/// a message row, and a row can be scrolled out of the tree — or the whole room
/// switched away — while the launch is still in flight, at which point the
/// context is no longer usable.
Future<void> openExternalUrl(BuildContext context, Uri url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  var launched = false;
  try {
    launched = await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    launched = false;
  }
  if (launched) return;

  await Clipboard.setData(ClipboardData(text: url.toString()));
  messenger?.showSnackBar(
    SnackBar(content: Text('Could not open a browser. Copied: $url')),
  );
}
