// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap/app_router.dart';
import 'theme/theme_controller.dart';

/// The keys on the two `ProviderScope`s a launch can put at the root.
///
/// A locked installation calls `runApp` twice: once for the lock screen, then
/// again for the app itself once the passphrase has opened the store. The
/// second call does not start a fresh tree — Flutter reconciles the new root
/// against the old one, and two `ProviderScope`s of the same type and key are
/// "the same widget, updated". Riverpod then asserts, because the scopes carry
/// different numbers of overrides (the gate knows only the preferences; the app
/// also knows the client, the passphrase and whether encryption is available)
/// and overrides may be updated but never added or removed.
///
/// Distinct keys are what make the second `runApp` *replace* the first scope
/// rather than update it, disposing the gate's container and building the app's
/// from scratch. They must stay different; that is the whole job.
const kUnlockScopeKey = ValueKey<String>('hardline-unlock-scope');
const kAppScopeKey = ValueKey<String>('hardline-app-scope');

/// Root widget.
///
/// Watching [themeDataProvider] here is the whole customization story: a
/// settings screen mutates the theme controller, `MaterialApp` rebuilds, and
/// every widget below recolors through `context.colors` without being touched.
class HardlineApp extends ConsumerWidget {
  const HardlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Hardline',
      debugShowCheckedModeBanner: false,
      theme: ref.watch(themeDataProvider),
      home: const AppRouter(),
    );
  }
}
