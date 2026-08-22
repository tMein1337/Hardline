// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Regenerates `THIRD_PARTY_NOTICES.md` from `pubspec.lock`.
///
/// Run it from the repository root, against the same checkout the release is
/// built from, whenever `pubspec.lock` changes:
///
/// ```
/// dart run tool/generate_third_party_notices.dart
/// ```
///
/// Add `--check` to verify the committed file is current without rewriting it;
/// that is the form the release checklist uses, and it exits non-zero when the
/// notices have drifted from the lockfile.
///
/// ## What it can and cannot do
///
/// It reads the *resolved* versions — never the ranges in `pubspec.yaml` — and
/// copies each package's license file verbatim out of the pub cache. It does
/// not paraphrase, summarise or substitute a license, because a notice file
/// that does any of those has stopped being a notice.
///
/// It covers Dart and Flutter packages. It does **not** cover the Flutter
/// engine, the Dart SDK, or the native libraries those bundle (BoringSSL,
/// Skia, libwebrtc and so on). Those are described in the "Platform and native
/// components" section of the generated file, and the app additionally ships
/// Flutter's own aggregated license registry, which the About screen shows
/// through `showLicensePage`.
library;

import 'dart:convert';
import 'dart:io';

const _outputPath = 'THIRD_PARTY_NOTICES.md';

/// Filenames a package may keep its license under, best first.
const _licenseNames = [
  'LICENSE',
  'LICENSE.md',
  'LICENSE.txt',
  'LICENCE',
  'LICENCE.md',
  'LICENCE.txt',
  'COPYING',
  'COPYING.txt',
  'UNLICENSE',
];

Future<void> main(List<String> args) async {
  final check = args.contains('--check');

  final lock = File('pubspec.lock');
  if (!lock.existsSync()) {
    stderr.writeln('pubspec.lock not found — run this from the repo root.');
    exit(2);
  }

  final packages = _parseLock(lock.readAsStringSync());
  if (packages.isEmpty) {
    stderr.writeln('No packages parsed out of pubspec.lock.');
    exit(2);
  }

  final cache = _pubCacheDir();
  final entries = <_Entry>[];
  final missing = <String>[];

  for (final package in packages) {
    final dir = _packageDir(cache, package);
    final license = dir == null ? null : _readLicense(dir);
    if (license == null && package.source == 'hosted') {
      missing.add('${package.name} ${package.version}');
    }
    entries.add(_Entry(package: package, licenseText: license));
  }

  final rendered = _render(entries);

  if (check) {
    final existing = File(_outputPath);
    if (!existing.existsSync()) {
      stderr.writeln('$_outputPath is missing. Run this without --check.');
      exit(1);
    }
    // Compared with the generation preamble stripped, so that re-running the
    // generator is not itself a diff.
    if (_comparable(existing.readAsStringSync()) != _comparable(rendered)) {
      stderr.writeln(
        '$_outputPath is out of date with pubspec.lock. '
        'Run: dart run tool/generate_third_party_notices.dart',
      );
      exit(1);
    }
    stdout.writeln('$_outputPath is up to date (${entries.length} packages).');
    return;
  }

  File(_outputPath).writeAsStringSync(rendered);
  stdout.writeln('Wrote $_outputPath for ${entries.length} packages.');

  if (missing.isNotEmpty) {
    // Loud, and a non-zero exit: shipping a notice file with a hole in it is
    // exactly the failure this tool exists to prevent. Usually it just means
    // `flutter pub get` has not been run against this lockfile yet.
    stderr
      ..writeln('')
      ..writeln('WARNING: no license file found in the pub cache for:')
      ..writeln(missing.map((m) => '  - $m').join('\n'))
      ..writeln('')
      ..writeln(
        'Run `flutter pub get`, then run this again. If a package genuinely '
        'ships no license file, resolve it with the package author before '
        'releasing.',
      );
    exit(1);
  }
}

/// One resolved package from the lockfile.
class _Package {
  const _Package({
    required this.name,
    required this.version,
    required this.source,
    required this.dependency,
  });

  final String name;
  final String version;

  /// `hosted`, `sdk`, `path` or `git`.
  final String source;

  /// `direct main`, `direct dev` or `transitive`.
  final String dependency;

  bool get isDirect => dependency.startsWith('direct');
}

class _Entry {
  const _Entry({required this.package, required this.licenseText});

  final _Package package;
  final String? licenseText;
}

/// A deliberately small reader for the one shape `pubspec.lock` has.
///
/// Depending on the `yaml` package would mean this tool could not run before
/// dependencies resolve, which is precisely when a broken lockfile needs
/// looking at.
List<_Package> _parseLock(String source) {
  final packages = <_Package>[];
  String? name, version, dependency, packageSource;

  void flush() {
    if (name != null) {
      packages.add(
        _Package(
          name: name!,
          version: version ?? 'unknown',
          source: packageSource ?? 'unknown',
          dependency: dependency ?? 'unknown',
        ),
      );
    }
    name = version = dependency = packageSource = null;
  }

  var inPackages = false;
  for (final raw in const LineSplitter().convert(source)) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;

    if (!raw.startsWith(' ')) {
      // A new top-level key ends the packages block (`sdks:` follows it).
      flush();
      inPackages = raw.startsWith('packages:');
      continue;
    }
    if (!inPackages) continue;

    final indent = raw.length - raw.trimLeft().length;
    final line = raw.trim();

    if (indent == 2 && line.endsWith(':')) {
      flush();
      name = line.substring(0, line.length - 1);
    } else if (indent == 4 && line.startsWith('dependency:')) {
      dependency = _scalar(line.substring('dependency:'.length));
    } else if (indent == 4 && line.startsWith('source:')) {
      packageSource = _scalar(line.substring('source:'.length));
    } else if (indent == 4 && line.startsWith('version:')) {
      version = _scalar(line.substring('version:'.length));
    }
  }
  flush();

  packages.sort((a, b) => a.name.compareTo(b.name));
  return packages;
}

String _scalar(String raw) {
  final trimmed = raw.trim();
  final quoted =
      trimmed.length >= 2 &&
      ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
          (trimmed.startsWith("'") && trimmed.endsWith("'")));
  return quoted ? trimmed.substring(1, trimmed.length - 1) : trimmed;
}

Directory _pubCacheDir() {
  final env = Platform.environment;
  final explicit = env['PUB_CACHE'];
  if (explicit != null && explicit.isNotEmpty) return Directory(explicit);

  if (Platform.isWindows) {
    final localAppData = env['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      final modern = Directory('$localAppData\\Pub\\Cache');
      if (modern.existsSync()) return modern;
    }
    final appData = env['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory('$appData\\Pub\\Cache');
    }
  }
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
  return Directory('$home/.pub-cache');
}

/// Where [package] unpacked in the cache, or null if it is not a hosted
/// package or has not been fetched.
Directory? _packageDir(Directory cache, _Package package) {
  if (package.source != 'hosted') return null;
  final sep = Platform.pathSeparator;
  final hosted = Directory('${cache.path}${sep}hosted');
  if (!hosted.existsSync()) return null;

  for (final host in hosted.listSync().whereType<Directory>()) {
    final dir = Directory(
      '${host.path}$sep${package.name}-${package.version}',
    );
    if (dir.existsSync()) return dir;
  }
  return null;
}

String? _readLicense(Directory dir) {
  for (final name in _licenseNames) {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) {
      final text = file.readAsStringSync().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

/// The generated file minus the counts that change with every resolve, for
/// `--check`.
String _comparable(String text) => text
    .split('\n')
    .where((line) => !line.startsWith('- Packages listed:'))
    .where((line) => !line.startsWith('- Declared directly'))
    .join('\n')
    .trim();

String _render(List<_Entry> entries) {
  final buffer = StringBuffer();
  final direct = entries.where((e) => e.package.isDirect).length;

  buffer
    ..writeln('# Third-party notices')
    ..writeln()
    ..writeln('Hardline is distributed under the GNU AGPLv3 or later. It is')
    ..writeln('built from, and ships with, third-party components that carry')
    ..writeln('their own licenses. Those licenses are reproduced below and')
    ..writeln('are **not** superseded by the license of Hardline itself.')
    ..writeln()
    ..writeln('Generated from `pubspec.lock` by')
    ..writeln('`tool/generate_third_party_notices.dart`. Regenerate it')
    ..writeln('whenever `pubspec.lock` changes, and verify it with')
    ..writeln('`--check` before tagging a release.')
    ..writeln()
    ..writeln('- Packages listed: ${entries.length}')
    ..writeln('- Declared directly by this project: $direct')
    ..writeln()
    ..writeln('## Platform and native components')
    ..writeln()
    ..writeln('The packages below are the Dart and Flutter layer. A built')
    ..writeln('release also contains components that are not resolved through')
    ..writeln('`pubspec.lock` and so are not listed individually here:')
    ..writeln()
    ..writeln('- The **Flutter SDK** and **Dart SDK** (BSD-3-Clause), and the')
    ..writeln('  native libraries the Flutter engine bundles — among them')
    ..writeln('  Skia, BoringSSL, ICU, HarfBuzz and libpng.')
    ..writeln('- **libwebrtc**, reached through `flutter_webrtc` and')
    ..writeln('  `livekit_client` (BSD-3-Clause), and the native codecs it')
    ..writeln('  carries.')
    ..writeln('- **vodozemac**, the Rust implementation of the Matrix')
    ..writeln('  cryptographic primitives, reached through')
    ..writeln('  `flutter_vodozemac` (Apache-2.0).')
    ..writeln('- **SQLite** (public domain), reached through')
    ..writeln('  `sqflite_common_ffi`. The library actually shipped is the')
    ..writeln('  **SQLite3 Multiple Ciphers** build of it (MIT, for its own')
    ..writeln('  code; the SQLite it embeds stays public domain), which is')
    ..writeln('  what provides the optional passphrase encryption of the')
    ..writeln('  local store. `package:sqlite3` selects it through the')
    ..writeln('  `hooks:` block in `pubspec.yaml` and downloads a prebuilt')
    ..writeln('  copy at build time, so it is not resolved through')
    ..writeln('  `pubspec.lock` and is not listed as a package below.')
    ..writeln('  See <https://github.com/utelle/SQLite3MultipleCiphers>.')
    ..writeln('- The **Microsoft Visual C++ runtime** — `msvcp140*.dll`,')
    ..writeln('  `vcruntime140*.dll` and `concrt140.dll` — which IS')
    ..writeln('  redistributed here, unmodified, beside the executable, so')
    ..writeln('  that the application runs without a separate prerequisite')
    ..writeln('  install. It is distributed under the redistributable terms')
    ..writeln('  of the Microsoft Visual Studio licence, remains a Microsoft')
    ..writeln('  component, and is not covered by the licence of this work.')
    ..writeln()
    ..writeln('The full, machine-collected set of engine and package licenses')
    ..writeln('for the exact build you are running is available inside the')
    ..writeln('application under **Settings → About → Open-source licenses**.')
    ..writeln()
    ..writeln('## Packages')
    ..writeln();

  for (final entry in entries) {
    final p = entry.package;
    buffer
      ..writeln('### ${p.name} ${p.version}')
      ..writeln()
      ..writeln('- Source: ${p.source}')
      ..writeln('- Dependency: ${p.dependency}');

    if (p.source == 'hosted') {
      buffer.writeln('- https://pub.dev/packages/${p.name}');
    }
    buffer.writeln();

    final license = entry.licenseText;
    if (license == null) {
      if (p.source == 'sdk') {
        buffer
          ..writeln('Shipped as part of the Flutter SDK; see the Flutter and')
          ..writeln('Dart SDK note above.')
          ..writeln();
      } else {
        buffer
          ..writeln('> **License text not found in the local pub cache.**')
          ..writeln('> Resolve this before releasing — see')
          ..writeln('> `tool/generate_third_party_notices.dart`.')
          ..writeln();
      }
      continue;
    }

    buffer
      // Fenced rather than indented so the text stays byte-identical to what
      // the package shipped.
      ..writeln('```text')
      ..writeln(license)
      ..writeln('```')
      ..writeln();
  }

  return buffer.toString();
}
