import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/features/settings/widgets/settings_layout.dart';
import 'package:matrix_client/theme/discord_palettes.dart';
import 'package:matrix_client/theme/discord_spacing.dart';
import 'package:matrix_client/theme/theme_builder.dart';

void main() {
  final theme = buildThemeData(DiscordPalettes.dark, DiscordMetrics.standard);

  Widget host(Widget child) =>
      MaterialApp(theme: theme, home: Scaffold(body: child));

  group('SettingsCard', () {
    // The voice pane puts a SwitchListTile in a card. While the card was a
    // plain coloured Container, ListTile's own assert fired: it paints its
    // background and ink on the nearest Material ancestor, which was above the
    // card and therefore behind its opaque background.
    testWidgets('is a Material, so a ListTile inside it can ink', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SettingsCard(
            child: SwitchListTile(
              value: true,
              title: const Text('Share system audio'),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('still draws its fill and outline', (tester) async {
      await tester.pumpWidget(host(const SettingsCard(child: Text('body'))));

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SettingsCard),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(material.color, DiscordPalettes.dark.elevatedSurface);
      expect(material.shape, isA<RoundedRectangleBorder>());
      expect(
        (material.shape! as RoundedRectangleBorder).side.color,
        DiscordPalettes.dark.divider,
      );
    });
  });
}
