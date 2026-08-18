// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Decides which MatrixRTC "focus" (SFU token service) this client is willing
/// to talk to.
///
/// ## Why this needs a policy at all
///
/// The focus is not configured locally. It is read out of
/// `org.matrix.msc3401.call.member` state events written by *other people in
/// the room*, and joining a call sends that host a Matrix **OpenID token**
/// obtained for our own account.
///
/// That token is not the access token — it grants no account access, and
/// handing it to a third party is what it is for. But it is a verifiable
/// assertion of our identity with a lifetime measured in minutes, and a service
/// that receives one can present it to anything that accepts Matrix OpenID and
/// be treated as us there. It also, unavoidably, reveals our IP address.
///
/// So the URL in that state event decides where an identity credential goes,
/// and any room member can set it.
///
/// ## What this policy does and does not fix
///
/// It cannot refuse third-party foci outright. A call is hosted on one SFU, and
/// everybody in it must reach the same one; rejecting a focus because it is not
/// ours would not make the call safer, it would put us alone in a parallel
/// call — the exact failure `livekit_token_service.dart` documents at length.
///
/// What it does:
///
///   * **Requires TLS.** An OpenID token must never cross the network in
///     cleartext. `http://` is accepted only for loopback, so that someone
///     running `lk-jwt-service` on their own machine can still develop.
///   * **Rejects anything that is not a plain absolute origin** — no
///     `user:pass@host` credentials, no query, no fragment. A base URL that
///     carries any of those is not a deployment address, it is someone being
///     clever.
///   * **Prefers our own homeserver.** When several foci are advertised and one
///     of them is on our homeserver's origin, that is the one used. This is
///     free — it picks a focus that is already correct for the call — and it
///     means the common case sends the token somewhere we already trust with
///     our whole account.
///
/// The residual exposure is documented in `PRIVACY.md` and `SECURITY.md` rather
/// than hidden: joining a call in a room controlled by someone else does tell
/// that someone else's chosen server who and where you are.
library;

import 'matrix_rtc_membership.dart';

/// Whether [raw] is a URL this client will send an OpenID token to.
bool isAcceptableFocusUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return false;

  if (!uri.isAbsolute || !uri.hasAuthority) return false;
  if (uri.host.isEmpty) return false;

  // Credentials in the URL, or a query/fragment on what should be a base
  // address, mean this is not a straightforward deployment URL.
  if (uri.userInfo.isNotEmpty) return false;
  if (uri.hasQuery || uri.hasFragment) return false;

  if (uri.scheme == 'https') return true;

  // Cleartext only where it cannot leave the machine.
  return uri.scheme == 'http' && _isLoopback(uri.host);
}

/// Whether [host] is genuinely this machine.
///
/// Parsed rather than prefix-matched. `127.0.0.1.evil.example` starts with
/// `127.` and is somebody else's server; a `startsWith` check here would hand
/// them an OpenID token over cleartext, which is the entire thing this file
/// exists to prevent.
bool _isLoopback(String host) {
  var bare = host.toLowerCase();
  if (bare.startsWith('[') && bare.endsWith(']')) {
    bare = bare.substring(1, bare.length - 1);
  }
  if (bare == 'localhost' || bare == '::1') return true;

  // A dotted quad, in full, with 127 in the first octet — nothing else.
  final octets = bare.split('.');
  if (octets.length != 4) return false;
  for (var i = 0; i < 4; i++) {
    final value = int.tryParse(octets[i]);
    if (value == null || value < 0 || value > 255) return false;
    if (i == 0 && value != 127) return false;
  }
  return true;
}

/// The scheme+host+port of [raw], or null if it is unusable.
String? focusOrigin(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.isAbsolute || !uri.hasAuthority) return null;
  try {
    return uri.origin;
  } on StateError {
    // `origin` throws for schemes it does not consider web-like.
    return null;
  }
}

/// Picks the focus to use for a call.
///
/// [advertised] is every focus named by a live participant, in the order they
/// were found. [homeserverOrigin] is our own homeserver's origin, used only as
/// a preference. [fallback] is what to use when the room offers nothing usable
/// — normally our homeserver's conventional service path.
///
/// Returns null when there is nothing acceptable at all, which the caller
/// surfaces as a failure to join rather than connecting somewhere arbitrary.
LiveKitFocus? chooseFocus({
  required List<LiveKitFocus> advertised,
  required String? homeserverOrigin,
  required LiveKitFocus? fallback,
}) {
  final usable = [
    for (final focus in advertised)
      if (isAcceptableFocusUrl(focus.serviceUrl)) focus,
  ];

  if (homeserverOrigin != null) {
    for (final focus in usable) {
      if (focusOrigin(focus.serviceUrl) == homeserverOrigin) return focus;
    }
  }

  if (usable.isNotEmpty) return usable.first;

  // The fallback is derived from our own homeserver, but it goes through the
  // same gate: a homeserver reached over plain http is not a reason to relax.
  if (fallback != null && isAcceptableFocusUrl(fallback.serviceUrl)) {
    return fallback;
  }
  return null;
}
