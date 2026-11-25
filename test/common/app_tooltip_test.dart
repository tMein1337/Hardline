// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/common/app_tooltip.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';

void main() {
  group('AppTooltip.position', () {
    TooltipPositionContext at(
      Offset center, {
      Size target = const Size(48, 48),
    }) => TooltipPositionContext(
      target: center,
      targetSize: target,
      tooltipSize: const Size(100, 20),
      verticalOffset: 24,
      overlaySize: const Size(800, 600),
    );

    test('below starts a gap under the bottom edge, however tall', () {
      final tall = at(const Offset(400, 300), target: const Size(48, 120));
      final position = AppTooltip.position(tall, TooltipSide.below);
      expect(position.dy, 300 + 60 + AppTooltip.gap);
      expect(position.dx, 350);
    });

    test('below flips above when the window ends', () {
      final position = AppTooltip.position(
        at(const Offset(400, 580)),
        TooltipSide.below,
      );
      expect(position.dy, 580 - 24 - AppTooltip.gap - 20);
    });

    test('right sits beside the target, vertically centred', () {
      final position = AppTooltip.position(
        at(const Offset(32, 100)),
        TooltipSide.right,
      );
      expect(position, Offset(32 + 24 + AppTooltip.gap, 90));
    });

    test('right flips left at the window edge', () {
      final position = AppTooltip.position(
        at(const Offset(770, 100)),
        TooltipSide.right,
      );
      expect(position.dx, 770 - 24 - AppTooltip.gap - 100);
    });

    test('is kept inside the window', () {
      final position = AppTooltip.position(
        at(const Offset(10, 300)),
        TooltipSide.below,
      );
      expect(position.dx, 8);
    });
  });

  testWidgets('a right-hand tooltip does not cover a tall target', (
    tester,
  ) async {
    const targetKey = Key('target');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(
          AppPalettes.dark,
          AppMetrics.standard,
          tooltipDelay: Duration.zero,
        ),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: AppTooltip(
                message: 'Test\nRight-click to manage',
                side: TooltipSide.right,
                child: SizedBox(key: targetKey, width: 58, height: 58),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byKey(targetKey)));
    await tester.pumpAndSettle();

    final message = find.text('Test\nRight-click to manage');
    expect(message, findsOneWidget);
    final target = tester.getRect(find.byKey(targetKey));
    final tooltip = tester.getRect(message);
    expect(tooltip.overlaps(target), isFalse);
    expect(tooltip.left, greaterThan(target.right));
    // Compact: two lines of the tooltip are less tall than the tile.
    expect(tooltip.height, lessThan(target.height));
    expect(find.byTooltip('Test\nRight-click to manage'), findsOneWidget);
  });
}
