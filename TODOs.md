<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# TODOs

What is left, and only that: finished work is in the git history, with the
reasoning in the commit messages.

Items 1 to 7 are the Windows app. Almost all of them are **verifications**:
the code is written and tested as far as one machine can test it, and what
remains needs Element, a second person, a game, or a homeserver configured a
particular way. Items 8 to 10 are the Nix packaging. The last two sections are
for later.

## 1. Verify settings, accounts and verification against Element

Everything in stage 4 is implemented but has only been exercised against
itself. What needs a second client:

1. **Fresh account, no other client.** Register an account, use only this app,
   run *Set up encryption*, save the recovery key. Then sign in to Element with
   that account and confirm it accepts the recovery key and sees this session
   as verified. This is the standalone case, and the one nothing else covers.
2. **Recovery key round trip** — enter a *wrong* recovery key and confirm the
   error is comprehensible rather than a stack trace.

The same session should settle item 5.1, which also needs Element.

## 2. The noise gate: what a test call cannot settle

`integration_test/call_flow.dart` checks the gate from the other end of a real
call — the app talking into VB-Audio's virtual cable, a second participant
measuring what arrives — and passes: no clipped onsets, no holes inside a
sentence, nothing at all when the breakpoint is too high, an encrypted call
surviving the gate being toggled, and the speaking ring at the far end. Run
it with the test accounts and the cable installed:

```powershell
flutter drive --driver=test_driver/integration_test.dart `
  --target=integration_test/call_flow.dart -d windows `
  --dart-define=HARDLINE_LIVE_ACCOUNTS=.claude/test-accounts.json
```

Two things it cannot judge, both for people:

1. **How quickly "immediately" is.** Switching the gate off should bring you
   back at once. The test asks for within 2s rather than within the ungated
   latency, because on this rig the listener's jitter buffer
   (`inbound-rtp.jitterBufferDelay`) climbs by roughly 100ms for every second
   of audio, gate or no gate — so anything measured late in a run carries a
   delay that is not the speaker's. The likeliest cause is the rig itself:
   both participants share one audio device in one process, playing out to a
   digital output with nothing plugged into it. Two machines would settle it.
2. **A real voice, with noise suppression on.** The test switches WebRTC's
   noise suppression off, because it takes the synthetic voice for noise and
   pulls it down within a second or two. Real speech is not treated that way,
   but nobody has listened to the gate with suppression on. Have somebody on
   the other end listen for clipped first syllables and words with holes in
   them, with the breakpoint set just above the room as the settings say.

**If the ring never appears for anybody**, check the log for
`microphone tap is delivering`. Its absence means the local half never started
and the remote half is measured separately — the two do not share a path, so
one working is not evidence about the other.

## 3. Verify the call grid and multiple screen shares

The grid replaces `CallStage` and is covered by tests that drive it from
hand-built values (`test/voice/call_grid_test.dart`,
`call_grid_layout_test.dart`, `live_participant_test.dart`). What no test can
cover is a real SFU with real video in it, and the list below needs a second
person because one participant cannot demonstrate a grid.

1. **Nine tiles.** Get to six or more streams between you and confirm the grid
   stays regular and the video stays smooth. `adaptiveStream` and `dynacast`
   are now on, so the SFU should be sending small layers for small tiles;
   without them this is where it would fall over.

## 4. Verify the call overlay over a real game, in a real call

Everything one person can check without a game is covered:
`integration_test/overlay_window_flow.dart` drives the real runner window and
the real second engine, in a debug build and an AOT one, and asserts from the
screen and from what Windows says about the window — transparency, the fade
and the linger, clicks falling through, staying on top, edit mode and a real
drag, the toggle chord pressed for real, the fallback from a missing monitor,
and capture exclusion. Layouts are covered by
`test/overlay/overlay_prefs_controller_test.dart`.

What needs a game, a second monitor, or a call with somebody in it:

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

## 5. The MatrixRTC ring is a revision behind the MSC

Checked against MSC4075 on 2026-10-18. There is still no call-ended event, and
inventing one is still wrong: MSC4310 (`m.rtc.decline`) was folded into
MSC4075, which says call endings and duration "are separate concerns". So the
derived past-tense row in `SystemEventTile` stays, and `io.hardline.*` stays
unwritten. What remains:

1. **The ring we send names an event type the MSC has renamed.** We send
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
   looks like success. Do it in the Element session of item 1: send the new
   spelling, confirm Element rings, and only then drop the old one.

2. **Declines are neither sent nor read.** `m.rtc.decline` is part of MSC4075
   now. Nothing in the client sends one when an invitation to a call is
   dismissed, and nothing reads one, so a declined call looks identical to an
   ignored one. Out of scope until the invite spelling above is settled, since
   a decline references the invite by event id and would otherwise reference an
   event type we had just stopped sending.

   An invite can now also be withdrawn — another one with the same
   `sticky_key` and empty content. That retracts the doorbell; it is not a
   record that the call ended, so it does not change the row either.

## 6. Verify the room and space administration against a real homeserver

**Built, and tested against a homeserver that is not one.** Room settings, a
member list with removal, bans and roles, a permissions page, taking a room out
of a space, a rail that nests, a paged hierarchy and a reader for
`m.space.parent` are covered against `FakeMatrixClient` — a real SDK `Client`
holding real `Room` state with the requests replaced — in `test/rooms/` and
`test/spaces/`, and clicked through in the real window by
`integration_test/room_admin_flow.dart`.

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

## 7. Registration stops where the browser has to start

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

## 8. Verify the NixOS package end to end on a clean machine

The Nix work builds and the process comes up, but "comes up" is all that has
been checked. `nix develop` + `flutter run -d linux` shows a window and
initialises E2EE; the hermetic `packages.default` is only verified as far as
*loading every native lib and reaching GTK display init* (see
`NIX-PACKAGING.md`) — not as a usable client. Nobody has run
`nix run github:tMein1337/Hardline` on a machine that is not this one, with no
checkout and no dev shell, and actually driven it.

**First, re-pin libwebrtc.** flutter_webrtc went from 1.6.0 to 1.6.3 for the
noise gate, and 1.6.3 asks for `libwebrtc.m150.7871.07`, while
`nix/flutter_webrtc.nix` still pre-fetches `m144.7559.09`. Until the URL and
hash there are updated from the plugin's `third_party/libwebrtc_version.ini`,
the Nix build is expected to fail at the plugin's CMake step, which will try
to download the release it does not find.

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
   but nothing is known to be missing. livekit_client implements
   `startVisualizer` in `linux/livekit_plugin.cpp` with the same `AddSink` on
   `RTCAudioTrack` that Windows uses, and `rtpSenderSetParameters` lives in
   flutter_webrtc's shared `common/cpp`. So this is a "run it and see", not a
   port.

   Four separate things, which fail independently:

   - **The ring for other people** is pure Dart over WebRTC statistics. If
     anything here works on Linux, this does.
   - **The meter** wants the native tap and falls back to statistics without it,
     so a bar that moves proves nothing about the tap. The log does:
     `microphone tap is delivering`.
   - **The gate** needs the tap, and refuses to switch on without it — the
     settings pane says so rather than offering a control that does nothing. If
     `startVisualizer` fails to build or to run under Nix, this is the half that
     goes missing, and it will say so on its own.
   - **The gate reopening.** While it is shut, `CaptureKeeper` holds a loopback
     sender open so the microphone goes on being read; on Windows, without it,
     the gate closed once and never opened again. Close the gate, then speak:
     it must open, and the log must say
     `capture keeper holding the microphone open`.

   Check `buildFlutterApplication` actually compiles livekit_client's Linux
   plugin, `shared_cpp` FFT sources and all. Nothing in `flake.nix` supplies a
   `customSourceBuilder` for it, so it goes through the generic path.
5. **On-device encryption refuses, and says why.** Until item 10 is done, the
   setting in `Settings → Security` must refuse to switch on under Nix and
   explain it — see "The store cipher is missing on Nix" in
   [NIX-PACKAGING.md](NIX-PACKAGING.md). That is the expected result, not a
   bug. (The way out of a forgotten passphrase is verified on Windows, by
   `integration_test/locked_launch_flow.dart`.)
6. **Non-NixOS via nixGL.** The `nix run --impure …#nixGLIntel -- nix run …`
   line in "Run on Linux with Nix" has never been run. Confirm it on a non-NixOS
   distro, and with the Nvidia variant if a card is available.
7. **A second build reproduces.** Delete the result and `nix build` again: the
   two fixed-output derivations (the libwebrtc zip, the pub cache) must still
   hash-match. A drifting hash is how a hermetic build quietly stops being one.
8. **It is an app, not just a binary.** The package ships a `.desktop` entry
   and a hicolor icon. Install it (`programs.hardline.enable`, or the overlay),
   rebuild, and confirm **Hardline shows up in the app menu with its icon**.
   Launch it **from the menu** — the window's dock/taskbar tile must show the
   Hardline icon, not a generic one; that is the tell that `StartupWMClass`
   matches the GTK app-id. Check **X11 and Wayland** separately.
9. **The cache actually serves.** After CI has pushed to Cachix, on a machine
   that never built this: `nix run --accept-flake-config github:tMein1337/Hardline`
   must **download** from `hardline.cachix.org` rather than compile (the log says
   `copying path … from 'https://hardline.cachix.org'`).

Once this passes, the "Run on Linux with Nix" section stops being a claim and
becomes a tested path. Read the log as well as the window: running past the
environment fixes is what surfaces the app-logic bugs sitting behind them, and
a first launch should come up with nothing in the log at all.

## 9. Publish a binary cache, and keep the nixpkgs pin fresh

Two Nix-distribution chores, separate from proving the build works (item 8).

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
verify, done *inside* an item-8 build-and-run pass — never a blind
`nix flake update` on faith.

## 10. Make on-device encryption work on the Nix build

Today it does not, and the app says so rather than pretending — `Settings →
Security` refuses to switch on, because `requireCipherSupport()` finds no
cipher and will not key a store with a library that would ignore the key. Item
8.5 checks that the refusal is what happens. **This item is about removing
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

**When it works, item 8.5 inverts** — the Linux package should then switch the
setting on rather than correctly refusing to. Update that point and the "The
store cipher is missing on Nix" section of [NIX-PACKAGING.md](NIX-PACKAGING.md),
which is where the detail lives, along with the `sqlite` comment in
`flake.nix`'s `runtimeLibsFor`.

## Later: platform support

- Linux (beyond the Nix package)
- macOS
- iOS
- Android

## Ideas

- Video streams inside the always-on-top overlay. Not possible as the overlay
  is built — a second Flutter engine cannot render the app engine's textures —
  but `DwmRegisterThumbnail` could mirror the grid's tiles into it. See "Which
  is also why the overlay cannot show video" in notes.md.
- The overlay on Linux and macOS. The Dart half is platform-agnostic already;
  what does not exist is the equivalent of `windows/runner/overlay_window.cpp`.
