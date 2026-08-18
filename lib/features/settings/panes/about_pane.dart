// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_info.dart';
import '../../../core/build_info.dart';
import '../../../theme/theme_context.dart';
import '../widgets/settings_layout.dart';
import 'document_viewer.dart';

/// **Settings → About**, and the app's Appropriate Legal Notices.
///
/// The AGPL asks an interactive program to offer a prominent, convenient way to
/// see the copyright notice, the absence of warranty, the terms it is conveyed
/// under, and how to read the licence. Section 13 additionally requires that
/// users can get at the Corresponding Source. This pane is where the app
/// discharges all of that.
///
/// The source link points at the **exact commit this binary was built from**,
/// not at a branch: a recipient is entitled to the source for the binary they
/// have, and `main` will have moved on. See `kSourceUrlForThisBuild`.
class AboutPane extends StatelessWidget {
  const AboutPane({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return SettingsPane(
      title: 'About',
      description: kAppTagline,
      children: [
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kAppName,
                style: text.title.copyWith(fontSize: 22, letterSpacing: 0.5),
              ),
              const SizedBox(height: 4),
              SelectableText(
                'Version $kVersionLine',
                style: text.timestamp.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 14),
              Text(kCopyright, style: text.subtitle),
              const SizedBox(height: 2),
              Text(
                'Licensed under the $kLicenseName ($kLicenseSpdx).',
                style: text.subtitle,
              ),
              const SizedBox(height: 12),
              // The no-warranty statement, verbatim in substance from the
              // licence itself. Not buried behind a link: it is one of the two
              // things section 5(d) wants shown.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.inputBackgroundAlt,
                  borderRadius: BorderRadius.circular(context.metrics.rowRadius),
                  border: Border(
                    left: BorderSide(color: colors.warning, width: 3),
                  ),
                ),
                child: Text(
                  kWarrantyNotice,
                  style: text.subtitle.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const SettingsLabel('Legal'),
        SettingsCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _AboutRow(
                icon: Icons.gavel_outlined,
                title: 'View GNU AGPLv3 License',
                subtitle: 'The full licence text, bundled with this build',
                onTap: () => DocumentViewer.open(
                  context,
                  title: 'GNU Affero General Public License v3',
                  assetPath: 'LICENSE',
                  externalUrl: kLicenseUrl,
                ),
              ),
              const _RowDivider(),
              _AboutRow(
                icon: Icons.code,
                title: 'Source code for this version',
                subtitle: kHasExactSource
                    ? 'Commit $kBuildCommit'
                    : 'Development build — opens the repository',
                onTap: () => _open(context, kSourceUrlForThisBuild),
                onCopy: () => _copy(context, kSourceUrlForThisBuild),
              ),
              const _RowDivider(),
              _AboutRow(
                icon: Icons.inventory_2_outlined,
                title: 'Open-source / third-party licenses',
                subtitle: 'Every component in this build, with its own licence',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: kAppName,
                  applicationVersion: kVersionLine,
                  applicationLegalese: '$kCopyright\n\n$kThirdPartyNotice',
                ),
              ),
              const _RowDivider(),
              _AboutRow(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy information',
                subtitle: 'What is stored locally, and what is sent where',
                onTap: () => DocumentViewer.open(
                  context,
                  title: 'Privacy information',
                  assetPath: 'PRIVACY.md',
                  externalUrl: kPrivacyUrl,
                ),
              ),
              const _RowDivider(),
              _AboutRow(
                icon: Icons.shield_outlined,
                title: 'Report a security issue',
                subtitle: 'Private disclosure, not a public issue',
                onTap: () => _open(context, kSecurityUrl),
                onCopy: () => _copy(context, kSecurityUrl),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const SettingsLabel('Independence'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kIndependenceNotice, style: text.subtitle),
              const SizedBox(height: 10),
              Text(kThirdPartyNotice, style: text.subtitle),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const SettingsLabel('Build'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BuildFact(label: 'Version', value: kAppVersion),
              _BuildFact(label: 'Commit', value: kBuildCommit),
              _BuildFact(label: 'Tag', value: kBuildTag),
              _BuildFact(label: 'Built', value: buildTimestamp),
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _open(BuildContext context, String url) async {
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

    // A machine with no browser association must still be able to get at the
    // source, so the fallback puts the URL somewhere the user can use it rather
    // than reporting a dead end.
    await Clipboard.setData(ClipboardData(text: url));
    messenger?.showSnackBar(
      SnackBar(content: Text('Could not open a browser. Copied: $url')),
    );
  }

  static Future<void> _copy(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: url));
    messenger?.showSnackBar(const SnackBar(content: Text('Link copied.')));
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onCopy,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Shown as a copy button when the row leads somewhere outside the app.
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: colors.textMuted, size: 20),
      title: Text(title, style: context.text.channelNameActive),
      subtitle: Text(
        subtitle,
        style: context.text.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onCopy case final copy?)
            IconButton(
              onPressed: copy,
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              color: colors.textMuted,
              tooltip: 'Copy link',
            ),
          Icon(Icons.chevron_right, color: colors.textFaint, size: 18),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.colors.divider);
}

/// One `label  value` line, with the value selectable so it can go straight
/// into a bug report.
class _BuildFact extends StatelessWidget {
  const _BuildFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label.toUpperCase(), style: context.text.fieldLabel),
          ),
          Expanded(
            child: SelectableText(value, style: context.text.timestamp),
          ),
        ],
      ),
    );
  }
}
