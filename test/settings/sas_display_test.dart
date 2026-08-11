import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/features/settings/verification/sas_display.dart';

void main() {
  group('resolveSasDisplay', () {
    test('honours the preference when both were negotiated', () {
      expect(
        resolveSasDisplay(
          SasDisplay.numbers,
          showsEmoji: true,
          showsDigits: true,
        ),
        SasDisplay.numbers,
      );
      expect(
        resolveSasDisplay(
          SasDisplay.emoji,
          showsEmoji: true,
          showsDigits: true,
        ),
        SasDisplay.emoji,
      );
    });

    // The preference is about readability; what is renderable is decided by the
    // protocol. Showing an empty box because the peer did not offer decimal
    // would make a working verification look broken.
    test('falls back to whatever the other side agreed to', () {
      expect(
        resolveSasDisplay(
          SasDisplay.numbers,
          showsEmoji: true,
          showsDigits: false,
        ),
        SasDisplay.emoji,
      );
      expect(
        resolveSasDisplay(
          SasDisplay.emoji,
          showsEmoji: false,
          showsDigits: true,
        ),
        SasDisplay.numbers,
      );
    });

    // Cannot happen against a spec-compliant client, but the dialog still has
    // to draw something rather than nothing.
    test('degrades to numbers when nothing was negotiated', () {
      expect(
        resolveSasDisplay(
          SasDisplay.emoji,
          showsEmoji: false,
          showsDigits: false,
        ),
        SasDisplay.numbers,
      );
    });
  });

  group('SasDisplay', () {
    // The stored value is the enum name, so renaming a case silently resets
    // everyone's preference.
    test('stores under stable names', () {
      expect(SasDisplay.values.map((v) => v.name), ['numbers', 'emoji']);
    });

    test('every case has something to put in the settings row', () {
      for (final value in SasDisplay.values) {
        expect(value.label, isNotEmpty);
        expect(value.description, isNotEmpty);
      }
    });
  });
}
