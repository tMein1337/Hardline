<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# TODOs

Items 1 to 4 and 8 to 9 are **verifications**, not features: the code is
written and believed correct, but has never been observed working, usually
because the test needs a second client or a second machine. Items 5 to 7 are the
Nix packaging: one verification and two pieces of work. Item 10 is what
survived the pass through `issues.md`; item 11 was built in the pass after
and is another verification; item 12 is left deliberately unfinished, with
the reason recorded.

## 1. Verify settings, accounts and verification against Element

Everything in stage 4 is implemented but has only been exercised against
itself. What needs a second client:

1. **Fresh account, no other client.** Register an account, use only this app,
   run *Set up encryption*, save the recovery key. Then sign in to Element with
   that account and confirm it accepts the recovery key and sees this session
   as verified. This is the standalone case, and the one nothing else covers.
2. **Recovery key round trip** — enter a *wrong* recovery key and confirm the
   error is comprehensible rather than a stack trace.

## 2. Verify the activity summary

Everything in stage 5 is implemented. What it needs is a second person, because
almost nothing in it can be triggered by the account watching it — you cannot
follow yourself, so every list is empty against a single account.

1. **Typing.** Have them start typing: the badge appears and clears on its own
   when they stop, without anything else arriving. Have them send: the row
   switches to a relative time and the message lands in the feed.
2. **Read receipts.** Have them send a message that mentions you: a badge
   appears. Open the room — it clears, and Element shows your read receipt
   moving. Then scroll **up** into history, have them send another, and confirm
   the badge does *not* clear until you scroll back down. Minimise the window,
   have them send one more, and confirm it survives being minimised.

## 3. Verify on-device encryption against a real account

1. **The way out** *(outstanding)*. On a throwaway install: lock it, forget
   the passphrase, use *"I have lost the passphrase"*, and confirm the app
   comes up at the login screen with the stores gone.
2. **Nix** *(outstanding)*. On the Linux package the setting must refuse to
   switch on and say why. That is expected, not a bug — see "The store cipher
   is missing on Nix" in [NIX-PACKAGING.md](NIX-PACKAGING.md), which has the
   two routes to fixing it.

## 4. Verify the speaking indicator and the noise gate with other people

**And the gate, from the other end** — everything below needs somebody
listening, because the entire question is what *they* hear:

1. **The gate actually gates.** Turn it on, set the breakpoint above your room
   noise, and stay quiet with a fan or a keyboard going. They should hear
   nothing. Then talk: they hear you, from the first syllable — a gate that
   clips word onsets is the usual failure and it is obvious to the listener
   long before it is obvious to you.
2. **No chopping inside sentences.** Talk normally, with the pauses a sentence
   has. They must hear continuous speech, not words with holes between them.
   That is the 400ms hold; if it is too short they will say you sound "cut up".
3. **The breakpoint set too high.** Deliberately set it above your speaking
   level and confirm they hear *nothing at all* — and that the meter shows you
   why. This is the failure mode the settings pane warns about, and it should
   be diagnosable from your own screen rather than only from their complaint.
4. **Encryption survives it.** The gate works by deactivating the RTP encoding
   on the sender, in a call that is end-to-end encrypted with a frame cryptor
   attached to that same sender. Toggling it repeatedly must not garble their
   audio or break it permanently. Nothing suggests it will; nothing has tested
   it either.
5. **Turning it off restores you.** Switch it off mid-call and confirm they
   hear you again immediately, without rejoining.

**If the ring never appears for anybody**, check the log for
`microphone tap is delivering`. Its absence means the local half never started
and the remote half is measured separately — the two do not share a path, so
one working is not evidence about the other.

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
4. **The speaking ring, the meter and the noise gate.** Unverified on Linux,
   but — unlike on-device encryption — nothing is known to be missing.
   livekit_client implements `startVisualizer` in `linux/livekit_plugin.cpp`
   with the same `AddSink` on `RTCAudioTrack` that Windows uses, and
   `rtpSenderSetParameters` lives in flutter_webrtc's shared `common/cpp`. So
   this is a "run it and see", not a port.

   Three separate things, which fail independently:

   - **The ring for other people** is pure Dart over WebRTC statistics. If
     anything here works on Linux, this does.
   - **The meter** wants the native tap and falls back to statistics without it,
     so a bar that moves proves nothing about the tap. The log does:
     `microphone tap is delivering`.
   - **The gate** needs the tap, and refuses to switch on without it — the
     settings pane says so rather than offering a control that does nothing. If
     `startVisualizer` fails to build or to run under Nix, this is the half that
     goes missing, and it will say so on its own.

   Check `buildFlutterApplication` actually compiles livekit_client's Linux
   plugin, `shared_cpp` FFT sources and all. Nothing in `flake.nix` supplies a
   `customSourceBuilder` for it, so it goes through the generic path.
5. **Non-NixOS via nixGL.** The `nix run --impure …#nixGLIntel -- nix run …`
   line in "Run on Linux with Nix" has never been run. Confirm it on a non-NixOS
   distro, and with the Nvidia variant if a card is available.
6. **A second build reproduces.** Delete the result and `nix build` again: the
   two fixed-output derivations (the libwebrtc zip, the pub cache) must still
   hash-match. A drifting hash is how a hermetic build quietly stops being one.
7. **It is an app, not just a binary.** The package now ships a `.desktop` entry
   and a hicolor icon. Install it (`programs.hardline.enable`, or the overlay),
   rebuild, and confirm **Hardline shows up in the app menu with its icon**.
   Launch it **from the menu** — the window's dock/taskbar tile must show the
   Hardline icon, not a generic one; that is the tell that `StartupWMClass`
   matches the GTK app-id. Check **X11 and Wayland** separately.
8. **The cache actually serves.** After CI has pushed to Cachix, on a machine
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
verify, done *inside* a TODO-5 build-and-run pass — never a blind
`nix flake update` on faith.

## 7. Make on-device encryption work on the Nix build

Today it does not, and the app says so rather than pretending — `Settings →
Security` refuses to switch on, because `requireCipherSupport()` finds no
cipher and will not key a store with a library that would ignore the key. TODO
3 step 2 verifies that refusal is what happens. **This item is about removing
the need for it.**

**Why it is missing.** `pubspec.yaml` asks `package:sqlite3` for the
SQLite3MultipleCiphers build through `hooks.user_defines`. Everywhere except
here that is honoured. nixpkgs carries its own source builder for the `sqlite3`
pub package which patches the build hook:

```nix
substituteInPlace lib/src/hook/compile/description.dart \
  --replace-fail "return fromGitHub(LibraryType.sqlite3);" "return LookupSystem('sqlite3');"
```

It has to: the unpatched hook downloads a prebuilt library from GitHub at build
time, which no hermetic build can allow. But the patch is unconditional, so it
overrides the request and links `pkgs.sqlite` — plain SQLite, which accepts
`PRAGMA key` and ignores it.

**Two routes, and they are not equivalent.**

1. **Package SQLite3MultipleCiphers in this flake**, and supply a
   `customSourceBuilders.sqlite3` of our own that patches to
   `LookupSystem('sqlite3mc')` instead. `flake.nix` already does exactly this
   shape for `flutter_webrtc`, whose builder pre-fetches a prebuilt library as
   a fixed-output derivation (`nix/flutter_webrtc.nix`) — so the pattern is
   established and the file to copy is sitting there.

   **Preferred, and the reason is on-disk format.** One cipher everywhere means
   one store format everywhere: a database written on Windows opens on Linux,
   and `store_cipher.dart` keeps its single pinned `chacha20` and its single
   set of pragmas. The cost is a `sha256` that only a real `nix build` can
   produce, which is why this could not be done from the machine the feature
   was written on.

2. **Use `pkgs.sqlcipher`**, which nixpkgs already has, patching to
   `LookupSystem('sqlcipher')`. Far less work. But SQLCipher is a *different*
   cipher with different pragmas and a different header: `store_cipher.dart`
   would have to learn both and choose at runtime, `requireCipherSupport()`
   would need to accept either, and a store written on one platform would not
   open on the other. Worth it only if route 1 proves impractical.

**When it works, TODO 3 step 2 inverts** — the Linux package should then pass
the whole of TODO 3 rather than correctly refusing its last step. Update that
step and the "The store cipher is missing on Nix" section of
[NIX-PACKAGING.md](NIX-PACKAGING.md), which is where the detail lives, along
with the `sqlite` comment in `flake.nix`'s `runtimeLibsFor`.

## 8. Verify the call grid and multiple screen shares

The grid replaces `CallStage` and is covered by tests that drive it from
hand-built values (`test/voice/call_grid_test.dart`,
`call_grid_layout_test.dart`, `live_participant_test.dart`). What no test can
cover is a real SFU with real video in it, and the list below needs a second
person because one participant cannot demonstrate a grid.

1. **Nine tiles.** Get to six or more streams between you and confirm the grid
   stays regular and the video stays smooth. `adaptiveStream` and `dynacast`
   are now on, so the SFU should be sending small layers for small tiles;
   without them this is where it would fall over.

## 9. Verify the call overlay over a real game, in a real call

**The gate has passed, and most of the list with it.** The overlay has been
seen working — by a screen capture rather than by a person, which is the
stricter witness. `integration_test/overlay_window_flow.dart` runs the real
runner window and the real second engine against a faked call, in a debug
build and in an AOT one, and asserts from what is on the screen and from what
Windows says about the window:

- **Transparency.** Outside the roster the monitor is pixel for pixel what it
  was before, and the colour key never reaches the screen.
- **The fade and the linger.** The window holds at full through pauses shorter
  than *Stay up for*, settles at exactly *Visible when silent* afterwards (the
  plate measured blended into what is behind it), disappears entirely at zero,
  and comes back whole when one person speaks.
- **Clicks fall through**, by Windows' own hit-testing at a pixel the HUD has
  painted; showing it does not take the foreground; it stays above a window
  that has just been activated.
- **Edit mode** takes the mouse and covers the monitor, a real drag comes back
  as a position in fractions of the monitor, and leaving it hands the desktop
  back.
- **The toggle chord**, pressed for real, hides it and brings it back.
- **A monitor that is not there** falls back to the primary one.
- **Capture exclusion.** With the setting on, the overlay is up and opaque and
  absent from a capture; switched off, it is in the next one.

Layouts shared between games, a deleted layout's games falling back, the last
layout refusing to go, and a dragged position surviving a restart are covered
in `test/overlay/overlay_prefs_controller_test.dart`.

What that cannot reach, because it needs a game, a second monitor, or a call
with somebody in it:

1. **Over a game.** Minecraft in Borderless Fullscreen: the HUD is there. The
   same game in true Fullscreen: it is not, and the app does not crash or hang
   waiting for it. The second half is the documented limitation behaving as
   documented — see "Exclusive fullscreen is out of reach" in
   [notes.md](notes.md).
2. **Alt-tab, repeatedly.** Switch to the app and back to the game a few
   times. The overlay must still be on top; that is what the two-second
   `HWND_TOPMOST` timer is for. The test covers one activation of an ordinary
   window, not a game re-asserting itself.
3. **The edit chord from inside a game.** The toggle chord is tested; the edit
   chord is driven through the controller rather than pressed, because edit
   mode takes the foreground and the test wants it back.
4. **The same place at a different resolution.** Change the game's resolution
   and confirm the HUD is in the same *place*, not at the same pixel.
5. **A layout following the game.** Assign a second executable to a layout
   and tab into it: the HUD should arrive already arranged. The lookup is
   tested; the foreground watch delivering the executable name is not.
6. **A real second monitor.** Put the overlay on it and confirm it covers
   that one; unplug it and confirm the overlay comes back on the primary.
7. **Capture exclusion, from the other end.** Share your screen and have
   somebody confirm they do not see your HUD. Windows 10 2004 is the floor;
   older builds fail the call and the overlay is simply visible.
8. **The graceful exit still works.** Close the window mid-call with the
   overlay showing. You must still disappear from the participant list at
   once — the overlay bridge sits in the same message pump as the exit request.
9. **Two engines, one process.** After using the overlay, check the log for
   anything from flutter_webrtc about a plugin registering twice, and confirm
   audio still works after the overlay has been shown and hidden a few times.

**Not implemented, deliberately:** the overlay cannot show video streams. That
is the architecture, not an omission — see "Which is also why the overlay cannot
show video" in [notes.md](notes.md), which also records the one route to it
(`DwmRegisterThumbnail`) if it is ever wanted.
## 10. The MatrixRTC ring is a revision behind the MSC

**Done, except for this.** The three things this section held are finished: the
overlay's two chords moved onto the shared hotkey registry, the denylist of
unshareable windows grew, and whether "a call ended" should be an event was
settled by reading the MSC rather than by guessing.

What that reading turned up is the item that remains. Checked 2026-10-18:

1. **There is still no call-ended event, and inventing one is still wrong.**
   MSC4310, which proposed `m.rtc.decline`, was closed as obsolete on
   2026-09-04 and folded into MSC4075; it states plainly that call endings and
   duration "are separate concerns". So the derived past-tense row in
   `SystemEventTile` stays the answer, and `io.hardline.*` stays unwritten.

   There *is* now a withdrawal mechanism, which is the nearest thing: an invite
   is retracted by sending another with the same `sticky_key` and empty
   content. That is a retraction of the doorbell, not a record that the call
   ended, so it does not change the row.

2. **The ring we send names an event type the MSC has renamed.** We send
   `org.matrix.msc4075.rtc.notification` carrying `notification_type`. MSC4075
   now defines `m.rtc.invite`, has **removed** `notification_type`, and has
   added `slot_id` and `sticky_key`. `matrix-js-sdk` is being updated to match
   (PR #5544), so current Element is moving to the new shape.

   The read side is already tolerant — `kRtcRingEventTypes` gained
   `org.matrix.msc4075.rtc.invite` and `m.rtc.invite`, which costs nothing
   because every use matches on the type alone and `isRingExpired` reads
   `sender_ts` and `lifetime`, both of which survive the rename.

   **The write side was deliberately not changed, and this is the judgement to
   re-make rather than inherit.** Two reasons. The MSC is still in review with
   open blocking questions and carries `needs-implementation`, so the shape may
   move again; and switching what we send is exactly the kind of change that
   cannot be verified alone — the whole point of the ring is that it makes
   *somebody else's* client notify, so a wrong guess is invisible from here and
   looks like success. Fold it into the §4 session with a second person: send
   the new spelling, confirm Element rings, and only then drop the old one.

3. **Declines are neither sent nor read.** `m.rtc.decline` is part of MSC4075
   now. Nothing in the client sends one when an invitation to a call is
   dismissed, and nothing reads one, so a declined call looks identical to an
   ignored one. Out of scope until the invite spelling above is settled, since
   a decline references the invite by event id and would otherwise reference an
   event type we had just stopped sending.


## 11. Verify the room and space administration against a real homeserver

**Built, and tested against a homeserver that is not one.** Everything this
section used to list as missing exists: room settings, a member list with
removal, bans and roles, a permissions page, taking a room out of a space, a
rail that nests, a hierarchy that is paged, and a reader for `m.space.parent`.
`test/rooms/` and `test/spaces/` cover it against `FakeMatrixClient` — a real
SDK `Client` holding real `Room` state with the requests replaced — and
`integration_test/room_admin_flow.dart` clicks through it in the real window.

What the fake cannot say is what a homeserver *refuses*. Every control is
gated on the power levels the client can read, and the authorisation rules
have corners that are easier to get wrong than to test for without one:

1. **A moderator's view.** In a room made by Element on Synapse, sign in as
   somebody at 50 and open the dialog. Name, topic and picture should be live;
   "what new members can read" and the permissions page should be text. Then
   try each live control — none may fail at the server. `canDescribe` was
   wrong in exactly this way before (it asked `events_default` about a state
   event), and that was found by reading, not by running.
2. **Roles.** Make somebody a moderator, then an admin; confirm Element shows
   the same, and that the row then offers nothing. Step yourself down and
   confirm the server accepts it and the dialog stops offering what you gave
   up.
3. **Lifting a ban** as somebody with the ban level but not the kick level.
   The dialog hides the button on the reading that it needs both. If Synapse
   accepts it anyway, the rule in `canUnbanMember` is too strict.
4. **"Anyone in its space."** Set it, then join from an account that is in the
   space and not invited to the room. Then remove that account from the space
   and confirm it can no longer join. This is the one setting whose whole
   effect is on somebody else.
5. **The directory switch.** It is gated on the level for
   `m.room.canonical_alias`, which is what servers ask for in practice and not
   something the specification promises. On a homeserver that only lets
   server admins publish, it will be offered and refused — the refusal is
   shown, but the switch should not have been there.
6. **A room with a few thousand members.** The list fetches `/members` once
   and writes the result into room state. Past 5000 it does not, and shows
   the fetch as it stood. Neither path has been seen at that size.
7. **A space with more than a hundred rooms**, for the paging, and one with a
   sub-space, to confirm `max_depth=1` returns the sub-space as an entry
   rather than nothing at all — the specification says it does, and the fake
   was written from the specification.

Left out on purpose, each because nothing in the client could finish the job:

- **Knocking.** A room already set to it is described, not offered: nothing
  here can answer a knock, so setting it would make a room nobody can enter.
- **Putting an existing room into a space.** Creating a room in one works and
  taking one out works. Adding needs a way to pick the room, which is a
  picker this app does not have yet.
- **A reason for a removal or a ban.** The API takes one. The dialog does not
  ask, because a required field in front of an urgent action is the wrong
  default and an optional one is a third control in a confirmation.
- **Levels other than 0, 50 and 100.** Shown for what they are when another
  client has set one; never set from here.
- **Checking a parent the room claims.** `m.space.parent` is the room's word
  for it, and is only to be believed if the space lists the room back — which
  cannot be seen without joining. It is shown as somewhere to go and look.
## 12. Registration stops where the browser has to start

`m.login.dummy`, `m.login.password`, `m.login.terms` and
`m.login.registration_token` are driven in-app. Anything else — a captcha, an
email address, a phone number — ends with the homeserver's own registration
page in a browser and an explanation naming the obstacle.

**That was the decision, not an oversight**, and the reason is the dependency:
`m.login.recaptcha` and `m.login.sso` both mean "render somebody else's web
page and let the user interact with it", which needs a webview this app does
not have and would carry for one screen. `m.login.email.identity` additionally
needs the client to poll while the user reads their mail and to hold a
registration open across a restart.

Revisit only if a webview arrives for some other reason. If it does, the shape
is already there: add the stage to `kSupportedRegistrationStages`, add a case
to `RegistrationController._handleStages`, and the flow selection and the
"blocked" wording follow on their own — `registrationBlockedReason` names each
obstacle separately precisely so it can stop naming one.

Also unverified, because it needs a homeserver that asks for each:

1. **A terms stage** — that the policy link is the right one, and in English
   where the server offers a choice. `_termsUrl` prefers `en` and falls back to
   whatever is first.
2. **A registration token stage.**
3. **`registrationPageFor`** is a *guess* — Element hosted at the homeserver's
   own domain, because there is no discovery for this. Wrong on a homeserver
   that hosts no web client, where it costs a browser tab.

## second to last Plattform Support
- Linux
- Macos
- iOS
- Android

## ideas
- Video streams inside the always-on-top overlay. Not possible as the overlay
  is built — a second Flutter engine cannot render the app engine's textures —
  but `DwmRegisterThumbnail` could mirror the grid's tiles into it. See "Which
  is also why the overlay cannot show video" in notes.md.
- The overlay on Linux and macOS. The Dart half is platform-agnostic already;
  what does not exist is the equivalent of `windows/runner/overlay_window.cpp`.
