// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/theme_context.dart';

/// A full-screen reader for a text document bundled with the build.
///
/// The licence and the privacy statement are shipped as assets and shown from
/// here rather than only linked, because a legal notice that needs a working
/// network connection and a browser is not reliably available at the moment
/// someone wants to read it.
///
/// The text is rendered monospaced and verbatim — no Markdown pass. For a
/// licence that is the point: what is on screen has to be the file, not a
/// rendering of it that dropped a line.
class DocumentViewer extends StatelessWidget {
  const DocumentViewer({
    super.key,
    required this.title,
    required this.assetPath,
    this.externalUrl,
  });

  final String title;

  /// An asset declared in `pubspec.yaml`.
  final String assetPath;

  /// Where the canonical copy lives, offered alongside the bundled one.
  final String? externalUrl;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required String assetPath,
    String? externalUrl,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentViewer(
          title: title,
          assetPath: assetPath,
          externalUrl: externalUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.timelineBackground,
      appBar: AppBar(
        backgroundColor: colors.roomSidebar,
        foregroundColor: colors.textHeader,
        elevation: 0,
        title: Text(title, style: context.text.title),
        actions: [
          if (externalUrl case final url?)
            IconButton(
              tooltip: 'Open the canonical copy in a browser',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () async {
                final messenger = ScaffoldMessenger.maybeOf(context);
                var launched = false;
                try {
                  launched = await launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (_) {
                  launched = false;
                }
                if (launched) return;
                await Clipboard.setData(ClipboardData(text: url));
                messenger?.showSnackBar(
                  SnackBar(content: Text('Copied: $url')),
                );
              },
            ),
        ],
      ),
      body: FutureBuilder<String>(
        future: DefaultAssetBundle.of(context).loadString(assetPath),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Should be unreachable — the asset is compiled in — but a legal
            // notice failing open with a blank screen would be the worst
            // possible way to find that out.
            return _Message(
              text:
                  'Could not read $assetPath from this build.\n'
                  '${externalUrl ?? ''}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 60),
              child: SelectableText(
                snapshot.data!,
                style: context.text.timestamp.copyWith(
                  fontSize: 12,
                  height: 1.5,
                  color: colors.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: SelectableText(text, style: context.text.subtitle),
    ),
  );
}
