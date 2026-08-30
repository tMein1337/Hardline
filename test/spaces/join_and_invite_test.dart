// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/spaces/widgets/invite_people_dialog.dart';
import 'package:hardline/features/spaces/widgets/join_space_dialog.dart';

void main() {
  group('joining a space by address', () {
    group('validateAddress', () {
      test('accepts an alias', () {
        expect(
          JoinSpaceDialog.validateAddress('#gaming:example.org'),
          isNull,
        );
      });

      // Rarer, but it is what a permalink carries and what somebody pasting
      // from `matrix.to` will have.
      test('accepts a room id', () {
        expect(
          JoinSpaceDialog.validateAddress('!abc123:example.org'),
          isNull,
        );
      });

      test('ignores surrounding space', () {
        expect(
          JoinSpaceDialog.validateAddress('  #gaming:example.org  '),
          isNull,
        );
      });

      test('asks for something when the field is empty', () {
        expect(JoinSpaceDialog.validateAddress('   '), isNotNull);
      });

      // The two halves people actually leave off, each named rather than
      // lumped into "invalid address".
      test('says which half is missing', () {
        expect(
          JoinSpaceDialog.validateAddress('gaming:example.org'),
          contains('#'),
        );
        expect(
          JoinSpaceDialog.validateAddress('#gaming'),
          contains('server'),
        );
      });
    });

    group('viaFor', () {
      // A space on a homeserver we have never spoken to is otherwise
      // unreachable: the local server cannot resolve an alias it has never
      // seen unless it is told where to look.
      test('takes the server from the address', () {
        expect(JoinSpaceDialog.viaFor('#gaming:example.org'), [
          'example.org',
        ]);
      });

      test('keeps a port', () {
        expect(JoinSpaceDialog.viaFor('#gaming:example.org:8448'), [
          'example.org:8448',
        ]);
      });

      test('is empty when there is no server to take', () {
        expect(JoinSpaceDialog.viaFor('#gaming'), isEmpty);
      });
    });
  });

  group('inviting people', () {
    test('accepts a user id', () {
      expect(
        InvitePeopleDialog.validateUserId('@alice:example.org'),
        isNull,
      );
    });

    test('ignores surrounding space', () {
      expect(
        InvitePeopleDialog.validateUserId('  @alice:example.org '),
        isNull,
      );
    });

    test('asks for something when the field is empty', () {
      expect(InvitePeopleDialog.validateUserId(''), isNotNull);
    });

    // People type the localpart, or the display name, or paste half of it.
    // Naming the missing part is more use than refusing the lot.
    test('says which half is missing', () {
      expect(
        InvitePeopleDialog.validateUserId('alice:example.org'),
        contains('@'),
      );
      expect(
        InvitePeopleDialog.validateUserId('@alice'),
        contains('server'),
      );
    });

    // A room alias is not a user id, and the shapes are close enough that
    // somebody will paste one.
    test('rejects a room alias', () {
      expect(
        InvitePeopleDialog.validateUserId('#gaming:example.org'),
        isNotNull,
      );
    });
  });
}
