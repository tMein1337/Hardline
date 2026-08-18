// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'sas_digits.dart';

/// One verification, wrapped so widgets can listen to it.
///
/// `KeyVerification` reports progress through a bare `onUpdate` callback rather
/// than a stream, so this adapts it to a [ChangeNotifier] instead of trying to
/// make it something it is not.
///
/// It also drives the two steps the SDK expects a client to take without asking
/// the user anything — see [_advance]. Leaving those to the UI would mean every
/// screen that starts a verification re-implements them, and forgetting one
/// looks like the other side simply never responding.
class VerificationSession extends ChangeNotifier {
  VerificationSession(this.request) {
    request.onUpdate = _onUpdate;
    // The request may already be past `askAccept` by the time we wrap it — an
    // outgoing one certainly is.
    _advance();
  }

  final KeyVerification request;

  /// Set once the session has been closed, so a late callback from the SDK
  /// cannot notify a disposed notifier.
  bool _closed = false;

  /// Which state [_advance] last acted on.
  ///
  /// The SDK calls `onUpdate` again from inside the very calls `_advance`
  /// makes, so without this the auto-continue would re-enter itself and send
  /// the same start event repeatedly.
  KeyVerificationState? _advancedFrom;

  KeyVerificationState get state => request.state;

  bool get isDone => request.isDone;

  /// True when this is one of our own sessions rather than another person's.
  bool get isSelfVerification =>
      request.userId == request.client.userID;

  /// The other side's device, when known. Null for an in-room request that has
  /// not picked one yet.
  String? get deviceId => request.deviceId;

  /// The decimal code, regrouped for reading. Empty outside [askSas].
  List<String> get digitGroups {
    final numbers = request.sasNumbers;
    if (numbers.length != 3) return const [];
    return sasDigitGroups(numbers);
  }

  /// The seven emoji, when the two sides agreed to that method.
  List<KeyVerificationEmoji> get emojis =>
      showsEmoji ? request.sasEmojis : const [];

  /// Which representations both ends agreed to.
  ///
  /// This is an intersection, not a choice: `short_authentication_string`
  /// carries every method each side knows, and both are usually left in it. So
  /// "emoji" and "decimal" are typically *both* valid, derived from the same
  /// shared secret, and each client independently decides which to draw.
  ///
  /// That is why showing only one used to make verification against Element
  /// impossible: Element leads with emoji, we drew digits, and the two are not
  /// comparable by eye even though the underlying check is identical. We now
  /// render everything that was agreed and let the user compare whichever their
  /// other device happens to show.
  bool get showsEmoji => request.sasTypes.contains('emoji');

  bool get showsDigits => request.sasTypes.contains('decimal');

  /// Why it ended, in the SDK's words. Null unless it was cancelled.
  String? get cancelReason => request.canceledReason ?? request.canceledCode;

  Future<void> accept() => _guard(request.acceptVerification);

  Future<void> reject() => _guard(request.rejectVerification);

  /// "They match" — the only step that actually asserts anything.
  Future<void> confirmMatch() => _guard(request.acceptSas);

  /// "They don't match" — cancels and, more importantly, refuses to sign.
  Future<void> denyMatch() => _guard(request.rejectSas);

  /// Unlocks secret storage so the result can actually be signed.
  ///
  /// Reached at [KeyVerificationState.askSSSS]: the account has cross-signing
  /// but this session has never held the keys, so it can mark the other device
  /// verified locally and publish nothing.
  Future<void> unlockSsss(String recoveryKey) =>
      _guard(() => request.openSSSS(keyOrPassphrase: recoveryKey.trim()));

  /// Continues without the recovery key.
  ///
  /// The verification still completes and still lets message keys flow, but no
  /// signature is published — so every other client goes on showing the session
  /// as unverified. [signedWithAccountKeys] reports which of the two happened.
  Future<void> skipSsss() => _guard(() => request.openSSSS(skip: true));

  /// Whether this client held the cross-signing keys needed to publish a
  /// signature others can check.
  ///
  /// The difference between a verification that changes what Element shows and
  /// one that only changes what we show. Resolved rather than stored because
  /// the answer changes during the flow — unlocking secret storage mid-way is
  /// exactly what [unlockSsss] is for.
  Future<bool> signedWithAccountKeys() async {
    final crossSigning = request.client.encryption?.crossSigning;
    if (crossSigning == null || !crossSigning.enabled) return false;
    return crossSigning.isCached();
  }

  /// Ends an unfinished verification. Safe to call on a finished one.
  Future<void> cancel() async {
    if (request.isDone) return;
    await _guard(() => request.cancel());
  }

  void _onUpdate() {
    if (_closed) return;
    _advance();
    notifyListeners();
  }

  /// Handles the states that have exactly one sensible answer.
  ///
  /// `askSSSS` is deliberately **not** one of them. It used to be auto-skipped,
  /// which produced a dialog reporting success while publishing nothing —
  /// leaving the user with a green tick here and a warning in Element and no
  /// way to connect the two. It is now a question, because it is one.
  void _advance() {
    if (_closed || _advancedFrom == request.state) return;
    _advancedFrom = request.state;

    switch (request.state) {
      case KeyVerificationState.askChoice:
        // **Only the side that sent the request may send the start.**
        //
        // Not a stylistic choice: getting this wrong produces different codes
        // on the two screens while every other part of the protocol reports
        // success. The SAS bytes come from an HKDF info string that names the
        // *start* sender first:
        //
        //     MATRIX_KEY_VERIFICATION_SAS|<starter>|<accepter>|<transaction>
        //
        // and the SDK picks that order from `startedVerification` — a flag it
        // sets in `sendRequest()`, so it really means "we sent the request".
        // The two only coincide when the requester is also the starter.
        //
        // Accepting a request and then starting from here breaks exactly that.
        // Both ends send a start, the SDK resolves the glare by sorting
        // `userId|deviceId`, and when *our* start wins we are the starter while
        // the flag still says we are not — so we build the info string in the
        // opposite order to the other client. Different bytes, different emoji,
        // different digits, and a failed MAC that Element reports as "your
        // messages are not secure". Whether it happens depends on how two
        // device ids sort, which is what made it look intermittent.
        //
        // Waiting is not a deadlock: the requester always sends a start by
        // itself. With QR unadvertised `isQrSupported` is false, and the SDK
        // sends the start straight from its ready handler without asking.
        if (!request.startedVerification) break;

        if (request.possibleMethods.contains(EventTypes.Sas)) {
          unawaited(
            _guard(() => request.continueVerification(EventTypes.Sas)),
          );
        } else {
          unawaited(_guard(() => request.cancel('m.unknown_method')));
        }

      case _:
        break;
    }
  }

  /// A failed step must not take the dialog down with it: the SDK has already
  /// moved the request to `error` with a reason, which is what the UI shows.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      debugPrint('Verification step failed: $error\n$stack');
    }
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    request.onUpdate = null;
    request.dispose();
    super.dispose();
  }
}

/// Plain-language endings, because `m.mismatched_sas` is not an explanation.
String describeVerificationEnd(VerificationSession session) {
  final code = session.request.canceledCode;
  return switch (code) {
    'm.mismatched_sas' =>
      'The codes did not match. Nothing was verified — if you did not expect '
          'this, someone may be intercepting the session.',
    'm.user' => 'Cancelled.',
    'm.timeout' => 'The other session did not respond in time.',
    'm.accepted' => 'Answered on another device.',
    null => session.cancelReason ?? 'Verification failed.',
    _ => session.cancelReason ?? 'Verification failed ($code).',
  };
}
