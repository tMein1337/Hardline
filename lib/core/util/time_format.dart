/// Discord-style time formatting.
///
/// Hand-rolled rather than pulling in `intl`: the app needs three fixed shapes,
/// and 24-hour time avoids a locale-dependent am/pm.
library;

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _two(int value) => value.toString().padLeft(2, '0');

/// `14:03`
String formatClockTime(DateTime time) =>
    '${_two(time.hour)}:${_two(time.minute)}';

/// `04/08/2026`
String formatShortDate(DateTime date) =>
    '${_two(date.day)}/${_two(date.month)}/${date.year}';

/// `Today at 14:03`, `Yesterday at 14:03`, or `04/08/2026 14:03`.
String formatMessageTimestamp(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final clock = formatClockTime(time);

  if (_isSameDay(time, reference)) return 'Today at $clock';
  if (_isSameDay(time, reference.subtract(const Duration(days: 1)))) {
    return 'Yesterday at $clock';
  }
  return '${formatShortDate(time)} $clock';
}

/// `just now`, `4 min ago`, `2 h ago`, `yesterday`, or `04/08/2026`.
///
/// For lists that answer "how fresh is this" rather than "when exactly was
/// this". Coarse on purpose: to the minute below an hour, to the hour below a
/// day, and a date beyond that, because nobody reads "3 h 47 min ago" as
/// anything more informative than "this afternoon".
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final elapsed = reference.difference(time);

  // A clock skewed against the homeserver's can put an event a few seconds in
  // the future. "in 4 seconds" reads as a bug, where "just now" is both true
  // enough and unremarkable.
  if (elapsed.inSeconds < 60) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
  if (_isSameDay(time, reference.subtract(const Duration(days: 1)))) {
    return 'yesterday';
  }
  return formatShortDate(time);
}

/// `Today`, `Yesterday`, or `4 August 2026` — for the date rule between days.
String formatDateSeparator(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();

  if (_isSameDay(date, reference)) return 'Today';
  if (_isSameDay(date, reference.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
