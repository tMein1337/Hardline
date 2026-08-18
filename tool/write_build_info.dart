// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Stamps `lib/core/build_info.dart` with the version, commit and tag this
/// build is being made from.
///
/// Run from the repository root immediately before `flutter build`:
///
/// ```
/// dart run tool/write_build_info.dart
/// ```
///
/// The AGPL entitles whoever has a binary to the source for *that* binary, so
/// the About screen has to be able to name the commit it came from. That is the
/// job this does, and it is why the release procedure refuses to continue when
/// the working tree is dirty: a stamped commit that does not describe the code
/// actually compiled would be worse than none.
///
/// `--reset` puts the placeholders back, which is what to run after a local
/// release build so the stamped values are not committed by accident.
library;

import 'dart:io';

const _outputPath = 'lib/core/build_info.dart';

Future<void> main(List<String> args) async {
  final reset = args.contains('--reset');
  final allowDirty = args.contains('--allow-dirty');

  // The version comes from pubspec.yaml either way; only the git-derived
  // fields are cleared by --reset.
  final version = _versionFromPubspec();
  final commit = reset ? 'unknown' : _git(['rev-parse', 'HEAD']) ?? 'unknown';
  final tag =
      reset
          ? 'unknown'
          : _git(['describe', '--tags', '--exact-match', 'HEAD']) ?? 'unknown';
  final timestamp = reset
      ? 'unknown'
      : DateTime.now().toUtc().toIso8601String();

  if (!reset) {
    final dirty = _git(['status', '--porcelain']);
    if (dirty != null && dirty.isNotEmpty) {
      final message =
          'Working tree is not clean. A stamped commit would not describe '
          'the code being built.\n'
          'Commit or stash first, or pass --allow-dirty for a local build.';
      if (!allowDirty) {
        stderr.writeln(message);
        exit(1);
      }
      stderr.writeln('WARNING: $message');
    }
    if (tag == 'unknown') {
      stderr.writeln(
        'NOTE: HEAD is not tagged. Fine for a test build; tag before a '
        'release so the About screen can link the release page.',
      );
    }
  }

  File(_outputPath).writeAsStringSync(_render(
    version: version,
    commit: commit,
    tag: tag,
    timestamp: timestamp,
  ));

  stdout.writeln(
    reset
        ? 'Reset $_outputPath to placeholders.'
        : 'Stamped $_outputPath: $version, commit $commit, tag $tag.',
  );
}

/// The `version:` line of `pubspec.yaml`, without the `+build` suffix.
String _versionFromPubspec() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found — run this from the repo root.');
    exit(2);
  }
  for (final line in pubspec.readAsLinesSync()) {
    if (line.startsWith('version:')) {
      return line.substring('version:'.length).trim().split('+').first;
    }
  }
  stderr.writeln('No version: line in pubspec.yaml.');
  exit(2);
}

/// Trimmed stdout of a git command, or null if git failed or is absent.
String? _git(List<String> args) {
  try {
    final result = Process.runSync('git', args);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  } on ProcessException {
    return null;
  }
}

String _render({
  required String version,
  required String commit,
  required String tag,
  required String timestamp,
}) =>
    '''
// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// GENERATED FILE — do not edit by hand.
///
/// Rewritten by `tool/write_build_info.dart`, which the release procedure runs
/// immediately before `flutter build`. It is committed with placeholder values
/// so that a fresh clone compiles without running the tool first; a development
/// build therefore reports `unknown`, which is what
/// `kHasExactSource` keys off.
library;

/// Marketing version, copied from `pubspec.yaml`.
const buildVersion = '$version';

/// The commit this build was made from, or `unknown`.
const buildCommit = '$commit';

/// The release tag this build was made from, or `unknown`.
const buildTag = '$tag';

/// UTC build timestamp in ISO-8601, or `unknown`.
const buildTimestamp = '$timestamp';
''';
