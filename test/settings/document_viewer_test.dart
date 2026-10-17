// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/settings/panes/document_viewer.dart';

void main() {
  group('DocumentViewer.trimmed', () {
    test('returns the document untouched when no marker is asked for', () {
      const text = 'one\ntwo\nthree';
      expect(DocumentViewer.trimmed(text, null), text);
    });

    // The marker moving must never blank the screen. A licence that renders
    // short because a string stopped matching is a worse failure than one that
    // renders a few paragraphs too many, and this is the only branch that can
    // tell the difference.
    test('returns the whole document when the marker is not present', () {
      const text = 'one\ntwo\nthree';
      expect(DocumentViewer.trimmed(text, 'NOT IN HERE'), text);
    });

    test('keeps the marker line and drops everything after it', () {
      const text = 'terms\nEND OF TERMS AND CONDITIONS\nappendix\nmore';
      expect(
        DocumentViewer.trimmed(text, 'END OF TERMS AND CONDITIONS'),
        'terms\nEND OF TERMS AND CONDITIONS',
      );
    });

    test('handles CRLF, since the bundled asset may carry it', () {
      const text = 'terms\r\nEND OF TERMS\r\nappendix\r\n';
      expect(
        DocumentViewer.trimmed(text, 'END OF TERMS'),
        'terms\r\nEND OF TERMS',
      );
    });

    test('keeps a document whose marker is the last line', () {
      const text = 'terms\nEND OF TERMS';
      expect(DocumentViewer.trimmed(text, 'END OF TERMS'), text);
    });
  });

  // Against the real file, because the point of the feature is what the About
  // screen shows — and because it fails loudly if the AGPL text is ever
  // replaced with a copy wrapped differently.
  group('the bundled LICENSE', () {
    final licence = File('LICENSE').readAsStringSync();

    test('still contains the marker the About screen cuts at', () {
      expect(licence, contains('END OF TERMS AND CONDITIONS'));
    });

    test('carries the appendix on disk but not in the viewer', () {
      const appendix = 'How to Apply These Terms to Your New Programs';
      expect(licence, contains(appendix));

      final shown = DocumentViewer.trimmed(
        licence,
        'END OF TERMS AND CONDITIONS',
      );
      expect(shown, isNot(contains(appendix)));
      // The terms themselves must all survive the cut.
      expect(shown, contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
      expect(shown, contains('15. Disclaimer of Warranty.'));
      expect(shown.trimRight(), endsWith('END OF TERMS AND CONDITIONS'));
    });
  });
}
