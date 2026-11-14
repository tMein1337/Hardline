// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:integration_test/integration_test_driver.dart';

/// The host half of `flutter drive`: waits for the application to report how
/// its tests went, and exits with that.
///
/// See `integration_test/all_test.dart` for why the suites are driven rather
/// than run through `flutter test`.
Future<void> main() => integrationDriver();
