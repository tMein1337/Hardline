<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Security policy

Hardline is an end-to-end encrypted communication client. Security reports are
welcome and taken seriously.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report privately through GitHub's private vulnerability reporting:

<https://github.com/tMein1337/hardline/security/advisories/new>

If that is unavailable to you, open a public issue containing **only** the words
"security contact request" and no details, and you will be given a private
channel.

Please include, as far as you can:

- What the issue is, and what an attacker gains from it.
- The Hardline version (**Settings → About**) and your operating system.
- Steps to reproduce, or a proof of concept.
- Anything that limits exploitability.

### What to expect

This is a single-maintainer project, so these are honest targets rather than
contractual commitments:

| Stage | Target |
|---|---|
| Acknowledgement of your report | within 7 days |
| Initial assessment | within 14 days |
| Fix or documented mitigation for a confirmed high-severity issue | within 90 days |

You will be credited in the release notes unless you prefer otherwise. There is
no bug bounty.

### Coordinated disclosure

Please give a reasonable window to ship a fix before publishing. If a report
concerns the Matrix protocol itself, the Matrix Dart SDK, `vodozemac`, LiveKit
or the Flutter engine rather than Hardline's own code, it usually belongs with
that project — say so and it will be forwarded rather than sat on.

## Supported versions

Only the **latest released version** is supported. There are no backports to
older releases.

## Scope

In scope — Hardline's own code:

- Handling of access tokens and encryption keys.
- Session teardown on sign-out.
- Parsing of untrusted input: room content, attachment filenames and MIME types,
  imported `.theme.json` files, URLs, and Matrix identifiers.
- Anything that causes secrets to be written to logs.
- The integrity of the release process and its published artifacts.

Out of scope:

- Your homeserver, or any call/SFU server. Those belong to their operators.
- Vulnerabilities in third-party dependencies with no Hardline-specific impact —
  report those upstream (though telling us is appreciated so the dependency can
  be bumped).
- Anything requiring an attacker who already has administrator access to the
  machine, or physical access to an unlocked session.

## Known limitations

Stated plainly, because they are design positions rather than oversights:

- **The local database is not encrypted at rest by default.** Out of the box,
  access tokens and encryption keys are protected only by operating-system file
  permissions and by whatever full-disk encryption is enabled.
  `Settings → Security` can turn on passphrase encryption of everything
  Hardline stores — see [`PRIVACY.md`](PRIVACY.md) for what that does and does
  not cover. Three limits of it are worth stating here:
  - It protects the files **at rest**. It does nothing against code running as
    you while the app is unlocked, which holds the passphrase in memory.
  - The passphrase is not recoverable. Hardline does not use the Windows
    credential store or DPAPI, and does not escrow the passphrase anywhere; a
    forgotten one means erasing the stored data.
  - Turning it on **cannot erase plaintext already written**. The database is
    re-encrypted in place, and fragments of the previous contents may remain in
    unused disk space. Full-disk encryption is what covers that.
- **On the Nix/Linux package, that setting is unavailable and says so.**
  nixpkgs builds `package:sqlite3` against the system SQLite, which has no
  cipher, so Hardline refuses to enable the feature there rather than appearing
  to encrypt and writing plaintext. See [`NIX-PACKAGING.md`](NIX-PACKAGING.md).
- **There is no auto-updater.** Updates are downloaded and installed manually,
  so there is no update channel to compromise — and no automatic delivery of
  security fixes either. Watch the releases page.
- **Release signing:** see [`RELEASING.md`](RELEASING.md) for the signing and
  checksum status of the current release, and always verify the published
  SHA-256 checksum of what you downloaded.
- **Call servers are nominated by the room, not by you.** Joining a call sends
  a Matrix OpenID token for your account to the SFU token service advertised in
  the room's MatrixRTC state, which any room member can set. That token grants
  no account access, but it is a verifiable assertion of your identity and it
  reveals your IP address. Hardline requires HTTPS for that address, rejects
  embedded credentials, and prefers a call server on your own homeserver when
  one is offered; it cannot refuse third-party call servers outright, because a
  call is hosted on exactly one SFU and everybody in it must reach the same
  one. See `lib/features/voice/focus_policy.dart`.
