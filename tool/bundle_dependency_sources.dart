// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Collects the source of every resolved Dart dependency into one directory,
/// so a release does not depend on pub.dev still serving those exact versions
/// years from now.
///
/// ```
/// dart run tool/bundle_dependency_sources.dart
/// ```
///
/// Writes `dist/dependency-sources/`, with one directory per package plus a
/// `MANIFEST.txt` listing name, version and the content hash from
/// `pubspec.lock`. Zip that directory and attach it to the release.
///
/// ## Why this exists
///
/// The AGPL obliges whoever conveys a binary to make the Corresponding Source
/// available for as long as the binary is offered. "It is on pub.dev" is an
/// assumption about somebody else's infrastructure, not an arrangement — a
/// package can be retracted, and a version can be pulled. Keeping a copy of the
/// exact sources the release was built from turns that assumption into
/// something under our own control.
///
/// This covers the Dart layer. The Flutter engine and the native libraries it
/// bundles are archived by pinning the Flutter SDK version recorded in
/// `RELEASING.md`.
library;

import 'dart:io';

const _outputDir = 'dist/dependency-sources';

Future<void> main(List<String> args) async {
  if (!File('pubspec.lock').existsSync()) {
    stderr.writeln('pubspec.lock not found — run this from the repo root.');
    exit(2);
  }

  final packages = _parseLock(File('pubspec.lock').readAsStringSync());
  final hosted = packages.where((p) => p.source == 'hosted').toList();
  if (hosted.isEmpty) {
    stderr.writeln('No hosted packages found in pubspec.lock.');
    exit(2);
  }

  final cache = _pubCacheDir();
  final out = Directory(_outputDir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  final manifest = StringBuffer()
    ..writeln('Dependency sources for Hardline')
    ..writeln('Resolved from pubspec.lock. One directory per package.')
    ..writeln('')
    ..writeln('name  version  sha256(from pubspec.lock)')
    ..writeln('');

  final missing = <String>[];
  var copied = 0;

  for (final package in hosted) {
    final from = _packageDir(cache, package);
    if (from == null) {
      missing.add('${package.name} ${package.version}');
      continue;
    }

    final to = Directory('${out.path}/${package.name}-${package.version}');
    _copyTree(from, to);
    copied++;
    manifest.writeln(
      '${package.name}  ${package.version}  ${package.sha256 ?? "-"}',
    );
  }

  File('${out.path}/MANIFEST.txt').writeAsStringSync(manifest.toString());
  File('${out.path}/pubspec.lock').writeAsStringSync(
    File('pubspec.lock').readAsStringSync(),
  );

  stdout.writeln('Copied $copied packages into $_outputDir');

  if (missing.isNotEmpty) {
    stderr
      ..writeln('')
      ..writeln('Not found in the pub cache:')
      ..writeln(missing.map((m) => '  - $m').join('\n'))
      ..writeln('')
      ..writeln('Run `flutter pub get` and try again.');
    exit(1);
  }
}

class _Package {
  const _Package({
    required this.name,
    required this.version,
    required this.source,
    this.sha256,
  });

  final String name;
  final String version;
  final String source;
  final String? sha256;
}

List<_Package> _parseLock(String source) {
  final packages = <_Package>[];
  String? name, version, packageSource, sha;

  void flush() {
    if (name != null) {
      packages.add(
        _Package(
          name: name!,
          version: version ?? 'unknown',
          source: packageSource ?? 'unknown',
          sha256: sha,
        ),
      );
    }
    name = version = packageSource = sha = null;
  }

  var inPackages = false;
  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;

    if (!line.startsWith(' ')) {
      flush();
      inPackages = line.startsWith('packages:');
      continue;
    }
    if (!inPackages) continue;

    final indent = line.length - line.trimLeft().length;
    final body = line.trim();

    if (indent == 2 && body.endsWith(':')) {
      flush();
      name = body.substring(0, body.length - 1);
    } else if (indent == 4 && body.startsWith('source:')) {
      packageSource = _scalar(body.substring('source:'.length));
    } else if (indent == 4 && body.startsWith('version:')) {
      version = _scalar(body.substring('version:'.length));
    } else if (indent == 6 && body.startsWith('sha256:')) {
      sha = _scalar(body.substring('sha256:'.length));
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

Directory? _packageDir(Directory cache, _Package package) {
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

void _copyTree(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: true)) {
    final relative = entity.path.substring(from.path.length + 1);
    if (entity is Directory) {
      Directory('${to.path}${Platform.pathSeparator}$relative')
          .createSync(recursive: true);
    } else if (entity is File) {
      final target = File('${to.path}${Platform.pathSeparator}$relative');
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
  }
}
