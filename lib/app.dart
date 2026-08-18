// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap/app_router.dart';
import 'theme/theme_controller.dart';

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
