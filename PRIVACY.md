<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Privacy information for Hardline

Last updated: 2026-08-18. Applies to Hardline 0.1.0.

This document describes what Hardline stores, what it sends, and to whom. It
describes the software as it is built from this repository. If you build a
modified version, this document may no longer be accurate for it.

## The short version

- Hardline is a **client**. It talks to the Matrix homeserver you sign in to,
  and to the call server that homeserver advertises. Nothing else.
- **The developer of Hardline receives nothing.** No telemetry, no analytics,
  no crash reporting, no update pings, no licence checks. There is no server
  operated by the developer for this application to talk to.
- Everything Hardline stores, it stores **locally on your computer**, in your
  own user profile.
- Hardline is not a hosted service. Whoever runs your homeserver — which may be
  you — is the party that actually processes your messages, and their privacy
  policy is the one that governs your account.

## What is stored on your computer

All application data lives under your Windows user profile, in the application
support directory:

```text
%APPDATA%\Mein1337\Hardline\
```

On Windows this path is derived from the executable's `CompanyName` and
`ProductName` resources; on Linux and macOS it is the equivalent per-user
application support directory. The preference store is a
`shared_preferences.json` file in that same directory.

### Account and session information

| What | Where | Notes |
|---|---|---|
| Access token, device id, user id, homeserver URL | Matrix SDK database (`matrix\*.sqlite`) | This is what keeps you signed in. Anyone who can read this file can act as your account until the session is revoked. |
| The list of accounts you have added, and which was last active | Windows preference store, key `accounts_v1` | Display names and homeserver hosts, so the account switcher can be drawn before any account is loaded. |
| The last homeserver you typed | Windows preference store, key `last_homeserver` | Convenience only, so the login field is prefilled. |

### Encryption keys

End-to-end encryption keys — your device keys, cross-signing keys, and the
Megolm session keys needed to read encrypted history — are held in the same
Matrix SDK database, managed by the Matrix Dart SDK and the `vodozemac`
cryptographic library.

**The database is not encrypted at rest by this application, and Hardline does
not currently use the Windows credential store or DPAPI.** It is protected by
your operating system's file permissions and by whatever full-disk encryption
you have enabled. On a machine where another person has an administrator
account, or on an unencrypted disk that is lost or stolen, treat these files as
readable.

### Message and room data

The same database holds a local copy of what your account can already see on the
server: rooms you are in, their state, the timeline you have loaded, room
members, read receipts and your own read markers.

### Attachments and media

| What | Where | Retention |
|---|---|---|
| Downloaded attachments and images | `matrix\files\` (per account) | Deleted automatically **30 days** after they are cached. |
| Large attachments | not cached | Anything over **10 MB** is re-fetched on demand rather than stored. |
| Avatars | in-memory and the platform HTTP image cache | Not written to a dedicated cache by this application. |

Files you explicitly save with **Save as** go wherever you put them, and
Hardline does not track them afterwards.

### Preferences

Stored in the Windows preference store (`shared_preferences`), which on Windows
is a JSON file inside the same application data directory:

| Key | Contents |
|---|---|
| `app_theme_v1` | Selected theme, tooltip delay |
| `theme_library_v1` | Your themes, including any you imported |
| `voice_prefs_v1:<user id>` | Chosen microphone and output device, per-person volumes and local mutes |
| `activity_prefs_v1:<user id>` | Which people you have chosen to follow |
| `sas_display_v1` | Whether verification shows emoji or numbers |

Per-person volume settings name the other person's user id and device id. They
never leave your computer.

### What is *not* stored

- Your password. It is sent to your homeserver to obtain a token and is not
  written to disk.
- Your recovery key or security passphrase. It is used in memory to unlock
  cross-signing and is not persisted by this application.

## What is sent, and where

### Your homeserver

Everything an ordinary Matrix client sends: authentication, sync, messages you
send, read receipts, presence if the server offers it, media uploads and
downloads, device and key management traffic.

Your homeserver operator can see everything a Matrix homeserver can see. For an
encrypted room that does not include message content, but it does include
metadata — who is in a room, when you are active, message sizes and timing.

### Call servers (MatrixRTC / LiveKit)

When you join a call, Hardline:

1. Reads the call server ("focus") advertised in the room's MatrixRTC state, or
   falls back to `<your homeserver origin>/livekit-jwt-service`.
2. Makes an HTTPS request to that JWT service to obtain a token, sending your
   user id, device id and the room identifier.
3. Connects to the LiveKit SFU named by that service and exchanges audio, video
   and screen-share media through it.

That server is operated by whoever runs the homeserver or the call
infrastructure for the room — **not** by the developer of Hardline. In an
encrypted room, media is end-to-end encrypted and the SFU relays it without
being able to decrypt it; the SFU still sees who is connected, from what IP
address, and for how long.

Your IP address is visible to your homeserver and to the call server, as it is
with any network client.

### Nobody else

There are no other outbound destinations. There is no analytics endpoint, no
error-reporting endpoint, and no update check.

## Device access

Hardline asks the operating system for these only when you use the matching
feature:

| Capability | When | Notes |
|---|---|---|
| **Microphone** | When you join a call, or change input device in settings. Enumerating devices may require permission. | Captured audio goes only to the call server for that call. Muting stops transmission. |
| **Camera** | Only when you turn your camera on in a call. | Off by default; never enabled without an explicit action. |
| **Screen sharing** | Only when you start a screen share and pick a source. | You choose the specific screen or window. |
| **System audio** | Only as part of a screen share, when you enable it. | Uses Windows loopback capture; captures the shared application's audio. |
| **Clipboard** | When you paste into the composer, or copy from the app. | Read only on an explicit paste. |
| **Drag and drop** | When you drop a file onto the window. | Reads the dropped file, including virtual files that have no path on disk. |
| **File dialogs** | When you attach a file or save one. | Only the files you pick. |

Hardline does not run in the background, does not register a startup entry, and
does not capture audio, video or the screen when you have not started a call or
a share.

## Removing your data

- **Sign out of an account:** Hardline deletes that account's database file and
  its cached attachment directory. See `deleteAccountStorage` in
  `lib/bootstrap/matrix_bootstrap.dart`.
- **Remove everything:** sign out of all accounts, close Hardline, and delete
  the application data directory named above.
- Deleting local data does not delete anything from your homeserver. To remove
  data there, use your homeserver's own account management, and revoke sessions
  from **Settings → Sessions** or from another client.

## Children

Hardline is a general-purpose communication client and is not directed at
children. Whether an account may be created is a matter for the homeserver
operator.

## Changes

This file is versioned in the repository. Each release ships the copy that was
current when it was built, and the history is visible in the source repository.

## Contact

Security issues: see [`SECURITY.md`](SECURITY.md).

Anything else: <https://github.com/Mein1337/hardline/issues>

## A note on scope

The developer of Hardline does not operate any service that processes user data
for this application, and therefore does not act as a controller or processor
for your messages. If that ever changes — telemetry, crash reporting, a hosted
sign-in, a relay, or any other developer-operated service — it will be
documented here **before** it is enabled, and it will be subject to a separate
data-protection review.
