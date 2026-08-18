// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/attachments/safe_filename.dart';

/// Every input here is something a remote sender can put on an `m.file` event,
/// so each case is an attack that reaches the save dialog rather than a
/// hypothetical.
String _c(int code) => String.fromCharCode(code);

void main() {
  group('ordinary names survive', () {
    test('a plain name is untouched', () {
      expect(safeFilename('report.pdf'), 'report.pdf');
      expect(safeFilename('holiday photo (2).jpeg'), 'holiday photo (2).jpeg');
    });

    test('non-Latin names are kept', () {
      expect(safeFilename('Bericht-Übersicht.pdf'), 'Bericht-Übersicht.pdf');
      expect(safeFilename('文書.txt'), '文書.txt');
    });

    test('a name with no extension is fine', () {
      expect(safeFilename('README'), 'README');
    });
  });

  group('directory components are stripped', () {
    test('traversal cannot pre-navigate the dialog', () {
      expect(
        safeFilename(r'..\..\..\Windows\System32\evil.dll'),
        'evil.dll',
      );
      expect(safeFilename('../../etc/passwd'), 'passwd');
    });

    test('an absolute path keeps only its last segment', () {
      expect(safeFilename(r'C:\Users\someone\thing.txt'), 'thing.txt');
      expect(safeFilename('/etc/shadow'), 'shadow');
    });

    test('a bare traversal token is not a name', () {
      expect(safeFilename('..'), kFallbackFilename);
      expect(safeFilename('.'), kFallbackFilename);
      expect(safeFilename(r'foo\..'), kFallbackFilename);
    });
  });

  group('invisible characters are removed', () {
    // The headline case: U+202E reverses the drawn order of what follows, so
    // the user reads ".png" and saves ".exe".
    test('a right-to-left override cannot disguise an extension', () {
      final spoofed = 'invoice${_c(0x202E)}gnp.exe';
      final cleaned = safeFilename(spoofed);

      expect(cleaned.contains(_c(0x202E)), isFalse);
      expect(cleaned, 'invoicegnp.exe');
      // What matters is that the real extension is the visible one.
      expect(cleaned.endsWith('.exe'), isTrue);
    });

    test('every bidi control is dropped', () {
      for (final code in [
        0x200E, 0x200F, // LRM, RLM
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, // embedding / override
        0x2066, 0x2067, 0x2068, 0x2069, // isolates
      ]) {
        final cleaned = safeFilename('a${_c(code)}b.txt');
        expect(cleaned, 'ab.txt', reason: 'U+${code.toRadixString(16)}');
      }
    });

    test('control characters and NUL are dropped', () {
      expect(safeFilename('re${_c(0x00)}port.pdf'), 'report.pdf');
      expect(safeFilename('re${_c(0x0A)}port.pdf'), 'report.pdf');
      expect(safeFilename('re${_c(0x1B)}port.pdf'), 'report.pdf');
      expect(safeFilename('re${_c(0x7F)}port.pdf'), 'report.pdf');
    });

    test('zero-width characters and a BOM are dropped', () {
      expect(safeFilename('re${_c(0x200B)}port.pdf'), 'report.pdf');
      expect(safeFilename('${_c(0xFEFF)}report.pdf'), 'report.pdf');
    });
  });

  group('characters Windows refuses', () {
    test('reserved punctuation becomes an underscore', () {
      expect(safeFilename('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
    });

    test('an alternate data stream cannot be addressed', () {
      // `file.txt:evil.exe` writes a hidden NTFS stream.
      expect(safeFilename('file.txt:evil.exe'), 'file.txt_evil.exe');
    });
  });

  group('Windows device names', () {
    test('reserved stems are defused', () {
      for (final name in ['CON', 'con', 'NUL', 'aux', 'COM1', 'lpt9']) {
        expect(safeFilename(name), '_$name');
      }
    });

    test('a reserved stem with an extension is still reserved', () {
      expect(safeFilename('CON.txt'), '_CON.txt');
      expect(safeFilename('nul.log'), '_nul.log');
    });

    test('a name that merely starts with one is left alone', () {
      expect(safeFilename('console.log'), 'console.log');
      expect(safeFilename('communication.txt'), 'communication.txt');
    });
  });

  group('trailing dots and spaces', () {
    // Windows strips these, so `evil.exe.` and `evil.exe` are one file that
    // looks like two.
    test('are removed', () {
      expect(safeFilename('evil.exe.'), 'evil.exe');
      expect(safeFilename('evil.exe   '), 'evil.exe');
      expect(safeFilename('evil.exe . . '), 'evil.exe');
    });

    test('a name of nothing but dots and spaces is rejected', () {
      expect(safeFilename('... '), kFallbackFilename);
      expect(safeFilename('   '), kFallbackFilename);
    });
  });

  group('length', () {
    test('a long name is clamped', () {
      final long = '${'a' * 500}.pdf';
      final cleaned = safeFilename(long);

      expect(cleaned.length, lessThanOrEqualTo(kMaxFilenameLength));
      // The extension is what says what the file is, so it is what survives.
      expect(cleaned.endsWith('.pdf'), isTrue);
    });

    test('a long name with no real extension is simply truncated', () {
      final cleaned = safeFilename('b' * 500);
      expect(cleaned.length, kMaxFilenameLength);
    });

    test('an absurd extension is treated as part of the stem', () {
      final cleaned = safeFilename('x.${'y' * 400}');
      expect(cleaned.length, lessThanOrEqualTo(kMaxFilenameLength));
    });
  });

  group('never returns something unusable', () {
    test('empty input falls back', () {
      expect(safeFilename(''), kFallbackFilename);
    });

    test('output is never empty, and never contains a separator', () {
      final inputs = [
        '', '.', '..', '/', r'\', '   ', '...', r'\\server\share',
        '${_c(0x202E)}${_c(0x200B)}', '<<<>>>', 'CON', 'a' * 1000,
        '${_c(0x00)}${_c(0x1F)}', 'a/b/c/', r'C:\\', '?*|',
      ];

      for (final input in inputs) {
        final out = safeFilename(input);
        expect(out, isNotEmpty, reason: 'input: ${input.codeUnits}');
        expect(out.contains('/'), isFalse, reason: 'input: $input');
        expect(out.contains(r'\'), isFalse, reason: 'input: $input');
        expect(out.length, lessThanOrEqualTo(kMaxFilenameLength));
      }
    });
  });
}
