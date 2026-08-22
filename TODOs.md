<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# TODOs

Items 1 to 4 are **verifications**, not features: the code is written and
believed correct, but has never been observed working, usually because the test
needs a second client or a second machine. Items 5 and 6 are the same shape for
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

## 5. Verify the NixOS package end to end on a clean machine

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

## 6. Publish a binary cache, and keep the nixpkgs pin fresh

Two Nix-distribution chores, separate from proving the build works (TODO 5).

**A binary cache (Cachix).** The heavy part of this build is the *build-time*
closure — the Flutter SDK, Dart, the Rust toolchain for the two cargokit
plugins, and the pub-cache FOD — none of which is in the runtime closure.
Without a cache every consumer rebuilds all of it from source; with one they
download only the runtime closure and never materialise the toolchain. This is
the single biggest thing for anyone consuming the flake.

The wiring is in place: `flake.nix` advertises the substituter via `nixConfig`,
and `.github/workflows/nix.yml` builds `.#hardline` on every push to `main` and
pushes it to Cachix. Three manual steps remain, which cannot be committed:

1. Create the `hardline` cache at cachix.org.
2. Replace `REPLACE_WITH_PUBLIC_KEY` in `flake.nix`'s
   `nixConfig.extra-trusted-public-keys` with the cache's real public key (and
   confirm the cache name/URL).
3. Add a write auth token as the `CACHIX_AUTH_TOKEN` repository secret so CI can
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
- **Optional encryption for the data stored on this device.** Everything is
  written in the clear today: `matrix_client.sqlite` holds the access token and
  the Megolm keys, and `matrix/files/` holds attachments already decrypted.
  `PRIVACY.md` and both release pages say so plainly, and full-disk encryption
  covers the case that matters most — a powered-off machine that walks away —
  which is why this is an idea and not a defect.

  What it would add is protection from another account on the same machine, and
  from a disk image lifted off it. It cannot protect against anything running
  *as the user*, because whatever the app can decrypt, malware wearing the same
  token can too. Say that out loud in the UI or it promises more than it does.

  The awkward part is the key, and it is a genuine trade rather than a detail.
  A passphrase typed at launch is real protection, but it blocks any unattended
  start and a forgotten one destroys the encrypted history for good. An OS
  keystore (DPAPI on Windows, libsecret on Linux) is invisible and unlosable,
  but it is only as strong as the OS account — which is exactly the threat above
  and no more. Opt-in, with the choice spelled out, is the only honest shape.

  Mechanically the database half is nearly free: `buildMatrixClient` hands
  `MatrixSdkDatabase.init` an already-open `Database`, so it is a swap of the
  factory. The cost is downstream — SQLCipher on desktop means shipping a
  SQLCipher-enabled sqlite3 in place of the stock `sqlite3.dll` this build
  bundles, so it lands on the Windows package and the Nix derivation both, and
  `sqflite_sqlcipher` is aimed at mobile and wants checking before it is
  assumed. The media cache needs its own answer regardless: `DatabaseFileStorage`
  writes ordinary files into `matrix/files/` and knows nothing about a cipher.

