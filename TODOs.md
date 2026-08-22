<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# TODOs

Items 1 to 5 are **verifications**, not features: the code is written and
believed correct, but has never been observed working, usually because the test
needs a second client or a second machine. Items 6 and 7 are the same shape for
the Nix packaging.

## 1. Verify screen-share system audio

Everything for this is implemented but it has never been observed working,
because no second client was available to listen. Until someone runs the test
below, treat it as unproven.

**How it is supposed to work.** `LiveKitCallController.startScreenShare` passes
`captureScreenAudio: true`, which `livekit_client` turns into `audio: true` in
the `getDisplayMedia` constraints (`track/local/local.dart`, `createStream`).
flutter_webrtc **1.5.0 or newer** turns that into a WASAPI loopback capture on
Windows and returns a second track, which LiveKit publishes as a separate
`screenShareAudio` track.

**The test.**

1. Settings (gear in the user footer) → *Voice & Video* → enable *"Share system
   audio when sharing a screen"*. It is off by default.
2. **Wear headphones.** Loopback capture can otherwise re-record the other
   participants and send them back to themselves.
3. Join a call in an unencrypted room with a second client present.
4. Share a window that is playing audio.
5. The other participant should hear it, and their right-click menu on you
   should show the *Screen Share Audio* slider **enabled** — it greys itself out
   when no `screenShareAudio` track exists, so that is the tell.
6. Move that slider and confirm it changes only the shared audio, not the voice.

**If no audio arrives**, check in this order:

- Does the sharer's log show a published `screenShareAudio` track? If not, the
  capture never happened and the problem is flutter_webrtc / Windows, not us.
- Is `shareSystemAudio` actually true in the stored prefs? It is read at share
  time, not at join time.
- Is the flutter_webrtc version still ≥ 1.5.0? Below that the feature does not
  exist and `audio: true` is silently ignored.

## 2. Verify settings, accounts and verification against Element

Everything in stage 4 is implemented but has only been exercised against
itself. What needs a second client:

1. **The shield is the acceptance test.** Send a message and look at it in
   Element. Before setup it shows "encrypted by a device not verified by its
   owner"; after Settings → Sessions → *Set up encryption* (or *Use
   recovery key*) it must show nothing. That single check is what the whole
   cross-signing path exists for — see "Why Element flags your messages" in
   [notes.md](notes.md).
2. **Fresh account, no other client.** Register an account, use only this app,
   run *Set up encryption*, save the recovery key. Then sign in to Element with
   that account and confirm it accepts the recovery key and sees this session
   as verified. This is the standalone case, and the one nothing else covers.
3. **Sessions** — the list should match Element's own Sessions screen. Rename a
   session here and see the new name in Element. Sign a *different* session out
   (it asks for the password) and watch it disappear from both.
4. **Verification, us → Element** — start it from Settings → Sessions &
   Security. Element shows emoji and we default to numbers, so use the dialog's
   *Switch* link; the emoji must then match glyph for glyph and name for name.
   Both sides should end verified, and the dialog must say whether a signature
   was actually published.
5. **Verification, Element → us** — start it from Element with our settings
   screen *closed*; the dialog has to appear anyway. Also try declining, and
   cancelling from each side mid-flow.
6. **Recovery key round trip** — enter a *wrong* recovery key and confirm the
   error is comprehensible rather than a stack trace.
7. **Accounts** — add a second account, switch back and forth, and confirm no
   room from one leaks into the other's list. Switch **while in a call** and
   confirm the other participants see you leave. Sign out of one account and
   confirm the app moves to the remaining one rather than to the login screen.

## 3. Verify the activity summary

Everything in stage 5 is implemented. What it needs is a second person, because
almost nothing in it can be triggered by the account watching it — you cannot
follow yourself, so every list is empty against a single account.

1. **The four follow controls agree.** Follow somebody by right-clicking their
   name in a chat, unfollow them from the voice participant menu, follow them
   again from the Activity page, and remove them in Settings → Activity. The
   four are one list; any of them disagreeing is the bug. Restart, and confirm
   it survived. Switch accounts and back: the list is per account, and the other
   account's must not appear.
2. **Placement.** With Home selected and no channel open, the Activity page
   fills the chat column. Clicking any channel replaces it. Inside a *space*
   with no channel open, the old "No room selected" placeholder is still what
   shows — the summary spans every room, so it belongs to Home alone.
3. **Voice.** Have them join a call: they appear under *In voice* within a sync,
   in a room you have never opened. The row's button says *Join* or *Enable &
   join*, and the second one must still show the power-level consent dialog.
   Join from there and the row switches to *You are here*.
4. **Typing.** Have them start typing: the badge appears and clears on its own
   when they stop, without anything else arriving. Have them send: the row
   switches to a relative time and the message lands in the feed.
5. **Jumping.** Click a message row. The channel opens — including switching the
   rail to its space — scrolls to that message, and washes it in the accent
   colour for a couple of seconds. Test three cases: a message in the room
   already open, one in a room in another space, and one far enough back to need
   a pagination step. A jump that cannot find the event must still mark it
   rather than silently doing nothing.
6. **The window really is a window.** Set it to 5 minutes and leave the app
   alone. Rows must age out **without anything being clicked** — that is the
   30 second sweep, and it is the only thing keeping "recently active" honest in
   a room that has gone quiet.
7. **Toggles.** Turn each of the three off and confirm the sections vanish
   independently and stay off across a restart.
8. **Backfill.** With it off, restart after they have said several things in
   several rooms: only the newest message per room is there. Turn it on — the
   catch-up runs at once, the progress line counts rooms, and the rest appears.
   Restart again: complete from the first frame. Check an **encrypted** room
   specifically — its history must arrive decrypted, and history no key is held
   for must be absent rather than showing "unable to decrypt" rows. Press *Catch
   up now* twice quickly and confirm the second press does nothing.
9. **Nobody followed** is the explainer with an *Add people* button, not four
   empty headings.
10. **Read receipts.** Have them send a message that mentions you: a badge
    appears. Open the room — it clears, and Element shows your read receipt
    moving. Then scroll **up** into history, have them send another, and confirm
    the badge does *not* clear until you scroll back down. Minimise the window,
    have them send one more, and confirm it survives being minimised.
11. **Dead call rings.** Have them start a call and leave without you joining.
    The timeline shows *"<their name> started a call"* with a green handset — the
    badge is now explicable rather than a red 1 over nothing — and within
    20 seconds or so it clears itself, without the room being opened. Then the
    safety case: have them send a real message **and** start a call, then leave
    the call — the badge must **stay**, because a receipt would clear the
    message too.
12. **The timeline is not buried.** Join and leave a call a few times and sit in
    one for several minutes. Exactly one line per call *start* appears; the
    joins, leaves and two-minute heartbeats must not, or the conversation
    disappears under call bookkeeping.

## 4. Verify the microphone switch and the hard-kill withdrawal

Two of the "Smaller things" below are fixed but unobserved. Both are I/O against
real hardware and a real homeserver, so nothing in the test suite covers them.

**Preflight, once.** The hard-kill fix has two independent halves and the first
only exists on a homeserver configured for it. Fetch
`/_matrix/client/versions` and look for `org.matrix.msc4140` in
`unstable_features`. Synapse advertises it **only** when
`max_event_delay_duration` is set in `homeserver.yaml` (e.g. `24h`). If it is
absent, steps 2 and 3 will not pass and are not supposed to — skip to step 4,
which is the half that works everywhere. The log says which path was taken:
*"delayed leave armed"* or *"homeserver does not support MSC4140"*.

**The microphone.** Needs a second person listening, and two physically
different microphones.

1. **Output is silent.** Join a call, talk, and change the *output* device
   mid-sentence. The other side must hear **no** interruption at all and see no
   mute indicator flicker. This used to republish the microphone for a change
   that has nothing to do with it.
2. **Input actually moves.** Change the *microphone* mid-call. Two separate
   things to confirm, and the second is the one that was broken: they keep
   hearing you across the switch, **and** they are now hearing the new
   microphone. Speak into only one of the two to tell. `logDiagnostics` prints
   `settings:` from the local track's `getSettings()` — it must name the new
   device. Before this fix the audio stayed on the old microphone while the
   settings dialog showed the new one, silently.
3. **Muted switching works.** Mute, change the microphone, unmute. The new
   device must be live. This never worked before.

**The hard kill.** Needs Element open on another account watching the channel.

1. **The graceful case still works.** Join, leave normally, and confirm you
   disappear at once — then that nothing is left scheduled behind you
   (`GET /_matrix/client/unstable/org.matrix.msc4140/delayed_events` empty).
   Regression check: the delayed leave must not outlive a clean leave.
2. **Killed mid-call.** Join, then end the process from Task Manager — not a
   window close, which runs the graceful path. Element must drop you from the
   participant list within ~20 s, with the app not running.
3. **Relaunch inside the window.** Join, kill, and relaunch and rejoin the *same
   call within 20 seconds*. You must **stay** in the participant list. This is
   the orphan-cancellation path, and if it is broken you will appear, sit there,
   and then silently vanish a few seconds later while still in the call.
4. **The sweep, on any homeserver.** Join, kill, relaunch and then leave the app
   alone — do not rejoin. The stale membership must clear itself shortly after
   the first sync, and Element must show you gone. This is what covers a
   homeserver without MSC4140.
5. **Another device is not collateral.** With a call joined on a *second* device
   or in Element, hard-kill this one and relaunch. The sweep must clear only
   this device's membership and leave the other call running.

## 5. Verify on-device encryption against a real account

`Settings → Security` → *"Encrypt the data stored on this device"* is
implemented and covered by tests that run against real sqlite files on disk
(`test/storage/`, `test/settings/device_encryption_test.dart`,
`test/auth/unlock_screen_test.dart`, `test/auth/launch_sequence_test.dart`).
What no test can cover is the app itself doing it to a live account, which is
what the list below is for.

**Steps 1 to 5 and 7 pass, observed on 2026-08-22** against a real account with
a second one added alongside it. Both stores were confirmed to begin with
ciphertext rather than `SQLite format 3`; the second account's store was born
encrypted rather than written in the clear and tidied up afterwards; the old
`matrix\files\` directory is gone; and `tool/inspect_store.dart` read
**11 attachments, 1.90 MB** back out of the encrypted main store — the
attachment cache is inside what the passphrase protects, which is the whole
claim. Turning it off and on again worked, as did changing the passphrase with
two accounts signed in, which was the step most likely to half-apply.

One bug was found doing it, and fixed. The first restart came up on a red screen
*after a correct passphrase*: a locked launch calls `runApp` twice, the second
call reconciled the lock screen's `ProviderScope` with the app's instead of
replacing it, and Riverpod refused the change in override count. Distinct scope
keys in `app.dart` are the fix, and `test/auth/launch_sequence_test.dart` pumps
the two real roots in order so it cannot come back silently.

**Steps 6 and 8 are outstanding**: the forgotten-passphrase path, which wants a
throwaway installation because it ends in deletion, and the Nix build, which
wants the machine. Everything else below is now a re-verification procedure
rather than an open question — worth re-running after anything touches
`lib/core/storage/` or the launch sequence.

**How it works, so a failure can be placed.** `pubspec.yaml` points
`package:sqlite3` at the SQLite3MultipleCiphers build, and
`lib/core/storage/store_cipher.dart` drives `PRAGMA key` / `PRAGMA rekey` on
top of it. The attachment cache moved *inside* the database
(`lib/core/storage/hardline_store.dart`) so that one key covers everything;
nothing decides to encrypt from a preference, only from the file header.

**The test.**

1. **Turning it on.** With a real, synced account: Settings → Security → the
   switch, a passphrase, *Encrypt*. The app must stay usable throughout — keep
   scrolling a timeline while it runs. Afterwards, `matrix_client.sqlite` must
   **not** start with the bytes `SQLite format 3`, and nothing may have been
   signed out.
2. **The lock screen.** Restart. It must ask, refuse a wrong passphrase with a
   message rather than a crash, accept the right one **after** that wrong
   attempt, and land in the shell with history intact and encrypted rooms still
   decrypting.
3. **A second account.** Add one while encryption is on and confirm its store is
   born encrypted (same header check). Then switch between the two, which is the
   path that opens a store the launch did not.
4. **Changing the passphrase, with two accounts signed in.** Both files must
   move. Restart and confirm the *old* one is refused and the new one works for
   whichever account was not active when it changed — that is the half that a
   half-applied change would break, and it would not show until then.
5. **Turning it off.** The header goes back to `SQLite format 3`, the launch
   stops asking, and everything still works.
6. **The way out** *(outstanding)*. On a throwaway install: lock it, forget
   the passphrase, use *"I have lost the passphrase"*, and confirm the app
   comes up at the login screen with the stores gone.
7. **Attachments.** Send and receive an image, restart, and confirm it is not
   re-downloaded — the cache is in the database now, and a broken blob table
   would look like nothing worse than a slow timeline. Check that
   `%APPDATA%\Mein1337\Hardline\matrix\files\` no longer exists.
8. **Nix** *(outstanding)*. On the Linux package the setting must refuse to
   switch on and say why. That is expected, not a bug — see "The store cipher
   is missing on Nix" in [NIX-PACKAGING.md](NIX-PACKAGING.md), which has the
   two routes to fixing it.

## 6. Verify the NixOS package end to end on a clean machine

The Nix work builds and the process comes up, but "comes up" is all that has
been checked. `nix develop` + `flutter run -d linux` shows a window and
initialises E2EE; the hermetic `packages.default` is only verified as far as
*loading every native lib and reaching GTK display init* (see
`NIX-PACKAGING.md`) — not as a usable client. Nobody has run
`nix run github:tMein1337/Hardline` on a machine that is not this one, with no
checkout and no dev shell, and actually driven it.

What still needs proving:

1. **`nix run` on a clean NixOS box.** A machine that has never built this,
   straight from the flake ref. It must render a real first frame — not merely
   reach display init — then log in, sync, and open a room. This is the path the
   README tells people to use and it is the least-exercised one.
2. **The GPU/window half specifically.** The wrapper bakes
   `/run/opengl-driver/lib` for exactly this; confirm a frame actually paints on
   both X11 and Wayland, since a bufferless Wayland surface is the silent failure
   that leaves a live process with no visible window.
3. **A call.** libwebrtc is the reason the whole runtime-libs dance exists.
   Joining a call, sending audio and screen-sharing is what proves the rpath'd
   `DT_NEEDED` libs (libgbm/libdrm/…) resolve at *runtime*, not just at link.
4. **Non-NixOS via nixGL.** The `nix run --impure …#nixGLIntel -- nix run …`
   line in "Run on Linux with Nix" has never been run. Confirm it on a non-NixOS
   distro, and with the Nvidia variant if a card is available.
5. **A second build reproduces.** Delete the result and `nix build` again: the
   two fixed-output derivations (the libwebrtc zip, the pub cache) must still
   hash-match. A drifting hash is how a hermetic build quietly stops being one.
6. **It is an app, not just a binary.** The package now ships a `.desktop` entry
   and a hicolor icon. Install it (`programs.hardline.enable`, or the overlay),
   rebuild, and confirm **Hardline shows up in the app menu with its icon**.
   Launch it **from the menu** — the window's dock/taskbar tile must show the
   Hardline icon, not a generic one; that is the tell that `StartupWMClass`
   matches the GTK app-id. Check **X11 and Wayland** separately.
7. **The cache actually serves.** After CI has pushed to Cachix, on a machine
   that never built this: `nix run --accept-flake-config github:tMein1337/Hardline`
   must **download** from `hardline.cachix.org` rather than compile (the log says
   `copying path … from 'https://hardline.cachix.org'`).

Once this passes, the "Run on Linux with Nix" section stops being a claim and
becomes a tested path. Running past the environment fixes is what surfaces the
app-logic bugs sitting behind them, so read the log as well as the window: the
unhandled Riverpod exception this list used to carry was found exactly that way.
It is fixed — `_LoginScreenState._submit` read `ref` after `signIn` returned, by
which point the router had already swapped the login screen for the shell — and
a first launch should now come up with nothing in the log at all.

## 7. Publish a binary cache, and keep the nixpkgs pin fresh

Two Nix-distribution chores, separate from proving the build works (TODO 6).

**A binary cache (Cachix).** The heavy part of this build is the *build-time*
closure — the Flutter SDK, Dart, the Rust toolchain for the two cargokit
plugins, and the pub-cache FOD — none of which is in the runtime closure.
Without a cache every consumer rebuilds all of it from source; with one they
download only the runtime closure and never materialise the toolchain. This is
the single biggest thing for anyone consuming the flake.

The wiring is in place: `flake.nix` advertises the substituter via `nixConfig`
and carries the cache's real public key, and `.github/workflows/nix.yml` builds
`.#hardline` on every push to `main` and pushes it to Cachix. One manual step
remains, which cannot be committed:

1. Add a write auth token as the `CACHIX_AUTH_TOKEN` repository secret so CI can
   push.

**Keep the pin on a recent `nixos-unstable`.** The input already tracks
`nixos-unstable`; the *revision* is what is frozen in `flake.lock`. The closer
that revision is to what an unstable-tracking consumer runs, the more low-level
libs (glibc, gtk3, glib, mesa) hash-identically and collapse to one shared copy
instead of two — free disk for consumers. A stale pin shares nothing.

**But a pin bump is not a no-op — it is the highest-risk change in the whole Nix
setup.** `nix flake update` can move the very things the build is pinned
against: the Flutter/Dart version (must satisfy `sdk: ^3.12.2`), nixpkgs'
built-in pub source builders (the `super_native_extensions` 0.9.1 mapping in
`flake.nix`), and the `cargoHash`es under `nix/`. Treat a bump as a change to
verify, done *inside* a TODO-6 build-and-run pass — never a blind
`nix flake update` on faith.

## second to last Plattform Support
- Linux
- Macos
- iOS
- Android

## last: Smaller things

- Only `http` and `https` links in a message are clickable. A bare `www.host`,
  a `mailto:` address and a `matrix:` URI are left as plain text on purpose:
  each would need a scheme invented for it, and the moment the target stops
  being exactly the characters on screen, a link stops being self-evident.
  Adding any of them means inventing that scheme, so they would need the
  confirmation in Settings → Security to be *mandatory* rather than a default
  that can be switched off. The same is true the day `formatted_body` is
  rendered — an `<a href>` can say anything — see the note in
  `message_body.dart`.

- On-device encryption takes a passphrase and nothing else. An OS keystore
  (DPAPI on Windows, libsecret on Linux) would make it invisible and unlosable,
  and was deliberately not built: it is only as strong as the OS account, which
  is most of what the feature is trying to defend against, and it would add a
  native plugin to two platforms to buy that. A passphrase is the option that
  actually delivers what the settings pane claims. If a keystore is ever added
  it belongs *beside* the passphrase as a stated, weaker choice — never as a
  silent default.

- Turning encryption on rewrites the database in place, so the plaintext pages
  it used to occupy are not scrubbed. Fixing that properly means writing a new
  file, fsync'ing it, and overwriting the old one — which on a modern SSD still
  does not guarantee erasure, because the drive decides where writes land. The
  settings pane says so instead of implying otherwise.

- Matrix device ids change on every logout/login, so per-device volumes are
  forgotten when someone re-authenticates. Inherent to keying by device — the
  LiveKit identity carries `@user:server:DEVICEID` and nothing else about the
  far end is stable, so there is nothing better to key on. Switching accounts
  does **not** lose them: the session is restored from its own database rather
  than re-authenticated, so the device id survives.

## ideas
- An always-on-top call overlay for use over a full-screen application.
- A live speaking indicator on the space rail, so an unopened room still shows
  that somebody in it is talking.
