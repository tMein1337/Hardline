// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/auth/registration_flow.dart';
import 'package:matrix/matrix.dart';

AuthenticationFlow _flow(List<String> stages) => AuthenticationFlow(stages);

void main() {
  group('chooseRegistrationFlow', () {
    test('takes a flow made only of supported stages', () {
      final chosen = chooseRegistrationFlow([
        _flow([AuthenticationTypes.dummy]),
      ]);
      expect(chosen?.stages, [AuthenticationTypes.dummy]);
    });

    // Getting three stages into a flow and hitting a captcha wastes the
    // username and password somebody just chose, so a partially supported flow
    // is no flow at all.
    test('refuses a flow with even one unsupported stage', () {
      expect(
        chooseRegistrationFlow([
          _flow(['m.login.terms', AuthenticationTypes.recaptcha]),
        ]),
        isNull,
      );
    });

    test('prefers the shortest complete flow', () {
      final chosen = chooseRegistrationFlow([
        _flow(['m.login.terms', 'm.login.registration_token']),
        _flow([AuthenticationTypes.dummy]),
      ]);
      expect(chosen?.stages, [AuthenticationTypes.dummy]);
    });

    test('picks the supported one when a captcha flow is also offered', () {
      final chosen = chooseRegistrationFlow([
        _flow([AuthenticationTypes.recaptcha, AuthenticationTypes.dummy]),
        _flow(['m.login.terms']),
      ]);
      expect(chosen?.stages, ['m.login.terms']);
    });

    test('is null when nothing is offered', () {
      expect(chooseRegistrationFlow(const []), isNull);
    });
  });

  group('nextRegistrationStage', () {
    test('returns the first stage when nothing is done', () {
      expect(
        nextRegistrationStage(_flow(['m.login.terms', 'x']), const []),
        'm.login.terms',
      );
    });

    // The server's `completed` list is authoritative. Some homeservers mark
    // dummy done without the client ever answering it.
    test('skips what the server considers complete', () {
      expect(
        nextRegistrationStage(
          _flow(['m.login.terms', AuthenticationTypes.dummy]),
          const ['m.login.terms'],
        ),
        AuthenticationTypes.dummy,
      );
    });

    test('is null once every stage is done', () {
      expect(
        nextRegistrationStage(
          _flow(['m.login.terms']),
          const ['m.login.terms'],
        ),
        isNull,
      );
    });
  });

  group('registrationBlockedReason', () {
    test('is null when a flow can be completed', () {
      expect(
        registrationBlockedReason([_flow([AuthenticationTypes.dummy])]),
        isNull,
      );
    });

    // Naming the obstacle is what makes the browser button beneath it make
    // sense. "Registration failed" would not.
    test('names a captcha', () {
      final reason = registrationBlockedReason([
        _flow([AuthenticationTypes.recaptcha]),
      ]);
      expect(reason, contains('captcha'));
    });

    test('names email verification', () {
      final reason = registrationBlockedReason([
        _flow([AuthenticationTypes.emailIdentity]),
      ]);
      expect(reason, contains('email'));
    });

    test('says so when the server offered nothing at all', () {
      expect(registrationBlockedReason(const []), contains('did not offer'));
    });
  });

  group('validateLocalpart', () {
    test('accepts an ordinary name', () {
      expect(validateLocalpart('alice'), isNull);
      expect(validateLocalpart('alice.smith_2'), isNull);
    });

    test('rejects an empty name', () {
      expect(validateLocalpart('   '), isNotNull);
    });

    // People type what they see in their own address, and being told which
    // half to keep is more use than "invalid username".
    test('explains a full user id rather than just refusing it', () {
      expect(validateLocalpart('@alice:example.org'), contains('without the'));
      expect(validateLocalpart('alice:example.org'), contains('server'));
    });

    test('rejects spaces and uppercase', () {
      expect(validateLocalpart('alice smith'), contains('spaces'));
      expect(validateLocalpart('Alice'), contains('lowercase'));
    });
  });

  group('validatePassword', () {
    test('accepts a matching pair', () {
      expect(validatePassword('hunter22', 'hunter22'), isNull);
    });

    test('catches a mismatch', () {
      expect(validatePassword('hunter22', 'hunter23'), contains('match'));
    });

    test('catches an empty or short password', () {
      expect(validatePassword('', ''), isNotNull);
      expect(validatePassword('short', 'short'), contains('8'));
    });
  });

  group('registrationPageFor', () {
    test('points at the homeserver own web client', () {
      expect(
        registrationPageFor(Uri.parse('https://example.org')).toString(),
        'https://example.org/#/register',
      );
    });

    test('keeps a non-default port', () {
      expect(
        registrationPageFor(Uri.parse('https://example.org:8448')).toString(),
        'https://example.org:8448/#/register',
      );
    });
  });
}
