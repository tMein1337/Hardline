// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Who this application says it is, and where its source can be found.
///
/// One place, because the same handful of strings appear in the About screen,
/// in the window title and in the release package — and a source link that
/// disagrees with the build it is shown in is worse than no link at all.
library;

import 'build_info.dart';

/// The product name, as shown to users.
const kAppName = 'Hardline';

/// One line of what this is, used in About and in package metadata.
///
/// Deliberately says *compatible with* rather than anything that could read as
/// an endorsement: this project is not affiliated with The Matrix.org
/// Foundation. See [kIndependenceNotice].
const kAppTagline =
    'An independent desktop client for the Matrix protocol, '
    'written in Flutter.';

/// Marketing version, from `pubspec.yaml`, stamped in at build time.
const kAppVersion = buildVersion;

/// The exact commit this build came from, or `unknown` for a build that did not
/// go through `tool/write_build_info.dart` — a local development build, in
/// practice.
const kBuildCommit = buildCommit;

/// The release tag this build was made from, if any.
const kBuildTag = buildTag;

/// True when this build can point at the exact source it was made from.
///
/// The About screen falls back to the repository root when this is false, and
/// says so, rather than showing a link that quietly points at the wrong code.
bool get kHasExactSource => kBuildCommit != 'unknown';

const kCopyright = 'Copyright (C) 2026 Mein1337';

const kLicenseName = 'GNU Affero General Public License v3.0 or later';
const kLicenseSpdx = 'AGPL-3.0-or-later';

/// The AGPL's "no warranty" statement, in the short form section 15 allows an
/// interactive program to display.
const kWarrantyNotice =
    'This program comes with ABSOLUTELY NO WARRANTY, to the extent permitted '
    'by applicable law. It is free software, and you are welcome to '
    'redistribute it under the conditions of the GNU AGPL version 3 or later.';

/// Required by Phase 6 of the release roadmap, and true: this project speaks
/// the Matrix protocol without being connected to the organisation behind it.
const kIndependenceNotice =
    '$kAppName is an independent project. It is not published, sponsored or '
    'endorsed by The Matrix.org Foundation C.I.C., by Google LLC, or by any '
    'other organisation. "Matrix" and "Flutter" are the trademarks of their '
    'respective owners.';

const kThirdPartyNotice =
    'Third-party components retain their own licenses, which are not '
    'superseded by the license of $kAppName itself.';

// ── Links ────────────────────────────────────────────────────────────────

const kRepositoryUrl = 'https://github.com/tMein1337/hardline';
const kIssuesUrl = '$kRepositoryUrl/issues';
const kLicenseUrl = 'https://www.gnu.org/licenses/agpl-3.0.html';
const kPrivacyUrl = '$kRepositoryUrl/blob/main/PRIVACY.md';
const kSecurityUrl = '$kRepositoryUrl/blob/main/SECURITY.md';

/// The source corresponding to *this* build.
///
/// A commit URL rather than a branch: the AGPL entitles a recipient to the
/// source for the binary they actually have, and `main` is not that. Falls back
/// to the repository root only for a build with no stamped commit, which is
/// never a released one.
String get kSourceUrlForThisBuild => kHasExactSource
    ? '$kRepositoryUrl/tree/$kBuildCommit'
    : kRepositoryUrl;

/// The release page for this version, where the binary and its source archive
/// sit beside each other.
String get kReleaseUrlForThisBuild => kBuildTag != 'unknown'
    ? '$kRepositoryUrl/releases/tag/$kBuildTag'
    : '$kRepositoryUrl/releases';

/// Version as shown to a user, with enough of the commit to identify the build
/// in a bug report.
String get kVersionLine {
  if (!kHasExactSource) return '$kAppVersion (development build)';
  final short = kBuildCommit.length >= 7
      ? kBuildCommit.substring(0, 7)
      : kBuildCommit;
  return '$kAppVersion ($short)';
}
