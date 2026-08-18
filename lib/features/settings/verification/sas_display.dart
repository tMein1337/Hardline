// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';

const _prefsKey = 'sas_display_v1';

/// Which representation of the short authentication string to put on screen.
///
/// Both come from the same shared secret and either is a complete check, so
/// this is purely about what is easier for a person to compare — not about
/// security. See `sas_digits.dart` for why the digits are the way they are.
enum SasDisplay {
  numbers('Numbers', 'Twelve digits, in four groups of three.'),
  emoji('Emoji', 'Seven pictures with their names, as Element shows them.');

  const SasDisplay(this.label, this.description);

  final String label;
  final String description;
}

/// What to show, given what the two sides actually agreed to.
///
/// The preference cannot override the protocol: `short_authentication_string`
/// is negotiated, and a method the other end did not offer is not renderable at
/// all. So this falls back rather than showing an empty box — a verification
/// with a client that only does emoji still works, it just ignores the
/// preference for that one exchange.
SasDisplay resolveSasDisplay(
  SasDisplay preferred, {
  required bool showsEmoji,
  required bool showsDigits,
}) {
  if (preferred == SasDisplay.emoji && showsEmoji) return SasDisplay.emoji;
  if (preferred == SasDisplay.numbers && showsDigits) return SasDisplay.numbers;
  return showsEmoji ? SasDisplay.emoji : SasDisplay.numbers;
}

/// Remembers the choice.
///
/// Flat key, not namespaced by account: this is a statement about which of two
/// things the person at this computer finds easier to read, which does not
/// change when they switch accounts. Same reasoning as the theme.
class SasDisplayController extends Notifier<SasDisplay> {
  @override
  SasDisplay build() {
    final raw = ref.watch(prefsProvider).getString(_prefsKey);
    return SasDisplay.values
            .where((value) => value.name == raw)
            .firstOrNull ??
        // Numbers by default: they are unambiguous to read aloud, where emoji
        // depend on both people naming the same picture the same way.
        SasDisplay.numbers;
  }

  Future<void> set(SasDisplay value) async {
    if (state == value) return;
    state = value;
    await ref.read(prefsProvider).setString(_prefsKey, value.name);
  }
}

final sasDisplayProvider = NotifierProvider<SasDisplayController, SasDisplay>(
  SasDisplayController.new,
);

/// Test seam for [SasDisplay] parsing, kept alongside the controller so the
/// stored representation has one definition.
@visibleForTesting
String sasDisplayStorageKey() => _prefsKey;
