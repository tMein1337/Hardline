// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Checks every resolved dependency against the OSV vulnerability database.
///
/// ```
/// dart run tool/check_dependency_advisories.dart
/// ```
///
/// Exits non-zero when any package in `pubspec.lock` has a known advisory, so
/// it can gate a release the same way `--check` gates the third-party notices.
///
/// ## Why this exists
///
/// Dart has no `npm audit`. `dart pub outdated` reports what is *old*, which is
/// not the same question — a two-year-old package with no advisories is fine,
/// and a package released last week can be vulnerable. OSV
/// (<https://osv.dev>) aggregates advisories across ecosystems, including Pub,
/// and answers the question that actually matters before shipping.
///
/// It covers the Dart layer only, because that is what `pubspec.lock` pins.
/// The Flutter engine and the native libraries it bundles move with the
/// Flutter SDK version recorded in `RELEASING.md`, and are tracked by keeping
/// that current.
///
/// Network access is required. With `--offline` it reports what it *would*
/// query and exits zero, so a build without connectivity is not blocked —
/// but a release must run it online.
library;

import 'dart:convert';
import 'dart:io';

const _osvBatchUrl = 'https://api.osv.dev/v1/querybatch';
const _osvVulnUrl = 'https://api.osv.dev/v1/vulns';

/// OSV rejects very large batches; well under any documented limit.
const _batchSize = 100;

Future<void> main(List<String> args) async {
  final offline = args.contains('--offline');

  final lock = File('pubspec.lock');
  if (!lock.existsSync()) {
    stderr.writeln('pubspec.lock not found — run this from the repo root.');
    exit(2);
  }

  final packages = _parseLock(lock.readAsStringSync())
      .where((p) => p.source == 'hosted')
      .toList();

  if (packages.isEmpty) {
    stderr.writeln('No hosted packages found in pubspec.lock.');
    exit(2);
  }

  stdout.writeln('Checking ${packages.length} packages against OSV…');

  if (offline) {
    for (final package in packages) {
      stdout.writeln('  would query ${package.name} ${package.version}');
    }
    stdout.writeln('\n--offline: nothing queried, nothing verified.');
    return;
  }

  final client = HttpClient();
  final findings = <_Finding>[];

  try {
    for (var i = 0; i < packages.length; i += _batchSize) {
      final batch = packages.skip(i).take(_batchSize).toList();
      final results = await _queryBatch(client, batch);

      for (var j = 0; j < batch.length; j++) {
        final ids = results.length > j ? results[j] : const <String>[];
        for (final id in ids) {
          findings.add(
            _Finding(
              package: batch[j],
              id: id,
              summary: await _summaryOf(client, id),
            ),
          );
        }
      }
      stdout.write('\r  ${(i + batch.length)}/${packages.length}   ');
    }
  } on SocketException catch (error) {
    stderr.writeln('\nCould not reach OSV: $error');
    stderr.writeln('Re-run when online. Do not release on an unchecked tree.');
    exit(2);
  } finally {
    client.close();
  }

  stdout.writeln();

  if (findings.isEmpty) {
    stdout.writeln('\nNo known advisories for any resolved dependency.');
    return;
  }

  stderr.writeln('\n${findings.length} advisory/advisories found:\n');
  for (final finding in findings) {
    stderr
      ..writeln('  ${finding.package.name} ${finding.package.version}')
      ..writeln('    ${finding.id}  https://osv.dev/vulnerability/${finding.id}')
      ..writeln('    ${finding.summary}')
      ..writeln();
  }
  stderr.writeln(
    'Resolve each one — upgrade, or record why it does not apply — before '
    'tagging a release.',
  );
  exit(1);
}

class _Package {
  const _Package({
    required this.name,
    required this.version,
    required this.source,
  });

  final String name;
  final String version;
  final String source;
}

class _Finding {
  const _Finding({
    required this.package,
    required this.id,
    required this.summary,
  });

  final _Package package;
  final String id;
  final String summary;
}

/// Returns, for each package in [batch], the advisory ids affecting it.
Future<List<List<String>>> _queryBatch(
  HttpClient client,
  List<_Package> batch,
) async {
  final body = jsonEncode({
    'queries': [
      for (final package in batch)
        {
          'package': {'name': package.name, 'ecosystem': 'Pub'},
          'version': package.version,
        },
    ],
  });

  final decoded = await _postJson(client, _osvBatchUrl, body);
  final results = decoded['results'];
  if (results is! List) return List.filled(batch.length, const <String>[]);

  return [
    for (final result in results)
      if (result is Map && result['vulns'] is List)
        [
          for (final vuln in result['vulns'] as List)
            if (vuln is Map && vuln['id'] is String) vuln['id'] as String,
        ]
      else
        const <String>[],
  ];
}

/// One-line description of an advisory, for the report.
Future<String> _summaryOf(HttpClient client, String id) async {
  try {
    final request = await client.getUrl(Uri.parse('$_osvVulnUrl/$id'));
    final response = await request.close();
    if (response.statusCode != 200) return '(no summary available)';
    final decoded =
        jsonDecode(await response.transform(utf8.decoder).join()) as Map;
    final summary = decoded['summary'] ?? decoded['details'];
    if (summary is! String || summary.isEmpty) return '(no summary available)';
    final flat = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 160 ? '${flat.substring(0, 160)}…' : flat;
  } catch (_) {
    return '(no summary available)';
  }
}

Future<Map<String, Object?>> _postJson(
  HttpClient client,
  String url,
  String body,
) async {
  final request = await client.postUrl(Uri.parse(url));
  request.headers.contentType = ContentType.json;
  request.write(body);

  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();

  if (response.statusCode != 200) {
    throw HttpException('OSV returned ${response.statusCode}: $text');
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, Object?>) {
    throw const HttpException('OSV returned an unexpected shape');
  }
  return decoded;
}

/// The same small lockfile reader the notice generator uses, for the same
/// reason: this has to work before dependencies resolve.
List<_Package> _parseLock(String source) {
  final packages = <_Package>[];
  String? name, version, packageSource;

  void flush() {
    if (name != null) {
      packages.add(
        _Package(
          name: name!,
          version: version ?? 'unknown',
          source: packageSource ?? 'unknown',
        ),
      );
    }
    name = version = packageSource = null;
  }

  var inPackages = false;
  for (final raw in const LineSplitter().convert(source)) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;

    if (!raw.startsWith(' ')) {
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
