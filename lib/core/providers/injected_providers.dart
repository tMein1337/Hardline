import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Services constructed in `main()` and injected via `ProviderScope.overrides`.
///
/// They are built imperatively before `runApp` rather than inside async
/// providers, for two reasons:
///
///  * The bootstrap has hard ordering (vodozemac before `Client`, sqflite ffi
///    before opening the database), which reads far better as straight-line
///    code than as a chain of providers.
///  * A `FutureProvider` can be disposed and rebuilt — by hot reload or
///    `ref.invalidate` — which would open a *second* sqlite handle on the same
///    file and construct a second `Client`. An override is created exactly once
///    by construction.
///
/// Each throws if read without an override, so a missing override fails loudly
/// at startup instead of silently producing a second instance.
Never _missingOverride(String name) => throw StateError(
  '$name was read without an override. It must be provided in '
  'ProviderScope(overrides: [...]) in main().',
);

/// The Matrix SDK client. Long-lived and mutable; see the rules in
/// `matrix_tick_provider.dart` before reading it inside a widget.
final clientProvider = Provider<Client>(
  (ref) => _missingOverride('clientProvider'),
);

/// Loaded once in `main()` so the theme can be read synchronously and the very
/// first frame is already correctly colored.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => _missingOverride('prefsProvider'),
);

/// Whether `vodozemac` initialised. When false the client still works, but
/// encrypted rooms cannot be decrypted.
final encryptionAvailableProvider = Provider<bool>(
  (ref) => _missingOverride('encryptionAvailableProvider'),
);
