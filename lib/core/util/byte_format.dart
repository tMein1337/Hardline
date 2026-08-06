/// Human-readable file sizes.
///
/// Hand-rolled for the same reason as `time_format.dart`: the app needs one
/// fixed shape, and `intl` would be a dependency for a dozen lines.
library;

const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

/// `340 KB`, `1.2 MB`, `12 B`.
///
/// Binary units (1024), matching what Windows Explorer reports, so a file's
/// size in the tray agrees with its size on disk.
///
/// One decimal below 10 and none above, which is how Discord shows it: `1.2 MB`
/// is useful, `12.4 MB` is noise.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';

  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }

  final rounded = value < 10 ? value.toStringAsFixed(1) : value.round().toString();
  return '$rounded ${_units[unit]}';
}
