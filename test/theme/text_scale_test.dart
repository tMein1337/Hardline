// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/theme/app_theme_state.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:hardline/theme/typography.dart';

void main() {
  group('AppThemeState.textScale', () {
    test('defaults to the designed size', () {
      expect(const AppThemeState().textScale, kDefaultTextScale);
    });

    test('round-trips through JSON', () {
      const state = AppThemeState(textScale: 1.25);
      expect(AppThemeState.fromJson(state.toJson()).textScale, 1.25);
    });

    // Clamped at parse rather than at use. A hand-edited 12 would otherwise
    // render an app whose settings pane could not be reached to put it back.
    test('clamps an out-of-range stored value', () {
      expect(
        AppThemeState.fromJson({'textScale': 12.0}).textScale,
        kMaxTextScale,
      );
      expect(
        AppThemeState.fromJson({'textScale': 0.1}).textScale,
        kMinTextScale,
      );
    });

    test('falls back when the value is missing or not a number', () {
      expect(AppThemeState.fromJson({}).textScale, kDefaultTextScale);
      expect(
        AppThemeState.fromJson({'textScale': 'big'}).textScale,
        kDefaultTextScale,
      );
    });

    test('counts towards equality', () {
      expect(
        const AppThemeState(textScale: 1.2),
        isNot(const AppThemeState()),
      );
    });
  });

  group('AppTypography.from', () {
    test('is unchanged at scale 1', () {
      final plain = AppTypography.from(AppPalettes.dark);
      final scaled = AppTypography.from(AppPalettes.dark, 1.0);
      expect(scaled.messageBody.fontSize, plain.messageBody.fontSize);
    });

    test('multiplies every named size', () {
      final plain = AppTypography.from(AppPalettes.dark);
      final big = AppTypography.from(AppPalettes.dark, 2.0);

      expect(big.messageBody.fontSize, plain.messageBody.fontSize! * 2);
      expect(big.timestamp.fontSize, plain.timestamp.fontSize! * 2);
      expect(big.title.fontSize, plain.title.fontSize! * 2);
      expect(big.badge.fontSize, plain.badge.fontSize! * 2);
      expect(big.fieldLabel.fontSize, plain.fieldLabel.fontSize! * 2);
    });

    // `sized` is how the handful of one-off sizes stay in step. Without it
    // they were literals in a `copyWith` and would have ignored the setting.
    test('carries the scale so one-off sizes can use it', () {
      expect(AppTypography.from(AppPalettes.dark, 1.5).sized(20), 30);
      expect(AppTypography.from(AppPalettes.dark).sized(20), 20);
    });
  });

  group('AppMetrics.scaled', () {
    test('returns the same instance at scale 1', () {
      const metrics = AppMetrics.standard;
      expect(identical(metrics.scaled(1.0), metrics), isTrue);
    });

    // Heights and gaps around text have to follow it, or the first thing a
    // larger setting does is clip the thing it enlarged.
    test('grows the heights and gaps', () {
      final big = AppMetrics.standard.scaled(2.0);
      expect(big.headerHeight, AppMetrics.standard.headerHeight * 2);
      expect(big.avatarSize, AppMetrics.standard.avatarSize * 2);
      expect(big.avatarGutter, AppMetrics.standard.avatarGutter * 2);
      expect(big.contentPadding, AppMetrics.standard.contentPadding * 2);
    });

    // The columns are structure, not text. Widening the channel list with the
    // font would take that space from the timeline, which is the part somebody
    // enlarging the text wants to read.
    test('leaves the column widths and corner radii alone', () {
      final big = AppMetrics.standard.scaled(2.0);
      expect(big.railWidth, AppMetrics.standard.railWidth);
      expect(big.sidebarWidth, AppMetrics.standard.sidebarWidth);
      expect(big.rowRadius, AppMetrics.standard.rowRadius);
      expect(big.railIconRadius, AppMetrics.standard.railIconRadius);
    });
  });

  group('buildThemeData', () {
    test('threads the scale into both extensions', () {
      final theme = buildThemeData(
        AppPalettes.dark,
        AppMetrics.standard,
        textScale: 1.5,
      );

      final type = theme.extension<AppTypography>()!;
      final metrics = theme.extension<AppMetrics>()!;

      expect(type.scale, 1.5);
      expect(
        type.messageBody.fontSize,
        AppTypography.from(AppPalettes.dark).messageBody.fontSize! * 1.5,
      );
      expect(metrics.headerHeight, AppMetrics.standard.headerHeight * 1.5);
    });
  });
}
