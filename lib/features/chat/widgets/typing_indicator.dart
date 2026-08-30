// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../typing_provider.dart';

/// Who is typing, between the timeline and the composer.
///
/// A fixed-height strip rather than one that appears and disappears: a row
/// that grows into existence pushes the composer down under somebody's cursor
/// mid-sentence, which is worse than a few pixels of empty space. The same
/// reasoning as the activity page's rows keeping their height.
class TypingIndicator extends ConsumerWidget {
  const TypingIndicator({super.key, required this.roomId});

  /// Tall enough for the line, which is `timestamp`-sized.
  static const _height = 18.0;

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sentence = typingSentence(ref.watch(typingUsersProvider(roomId)));

    return SizedBox(
      height: _height,
      child: sentence == null
          ? null
          : Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.metrics.contentPadding,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  sentence,
                  style: context.text.timestamp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
    );
  }
}
