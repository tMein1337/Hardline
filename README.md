# matrix_client

A Matrix client with a Discord-like interface, written in Flutter. Primary
target is Windows desktop.

Written in English to match the code comments.

## Status

**Stage 1 — messaging.** Login, spaces, room list, reading and writing messages.

**Stage 2 — voice and video.** Feature-complete. One capability is built but
still unverified, because testing it needs a second person:

| Feature | State |
|---|---|
| Join / leave a call | works |
| See who is in a call **without joining** | works |
| Switch channels while in a call | works |
| Leave the call when the app closes | works |
| Microphone / output device selection, remembered | works |
| Mute, deafen | works |
| Per-user volume (voice + screen audio), remembered | works |
| Receive video, send camera | works |
| Screen sharing (source picker) | works |
| **Screen share system audio** | **built, not yet verified — see TODO** |
| Calls in encrypted rooms (E2EE media) | works, verified against Element |

**Stage 3 — file attachments.** Built, awaiting a pass against Element:

| Feature | State |
|---|---|
| Drag and drop onto the chat | built |
| Attach button (system file dialog) | built |
| Paste an image or a copied file | built |
| Staging tray, multiple files, per-file removal | built |
| Caption on a single attachment (MSC2530) | built |
| Attachments in encrypted rooms | built |
| Images shown inline | built |
| Files as a card with save-as | built |
| Upload progress, retry after failure | built |
| Video poster frame for videos **we** send | not supported — see below |
| Inline video/audio playback | out of scope for now |

**Stage 4 — settings, accounts and verification.** Built, awaiting a pass
against Element:

| Feature | State |
|---|---|
| Unified full-screen settings (gear in the user footer) | built |
| Voice & video settings, moved in from their own dialog | built |
| Appearance: presets and per-slot color overrides | built |
| Appearance: tooltip hover delay | built |
| Profile: display name and avatar | built |
| Several accounts, one signed in at a time, fast switching | built |
| Session list: rename, sign out remotely | built |
| Verifying your own sessions (decimal SAS) | built |
| Cross-signing set up from scratch, with a recovery key | built |
| Joining an existing cross-signing identity by recovery key | built |
| Encrypted message-key backup | built (as part of setup) |
| QR verification | out of scope until mobile |

## Running

```
flutter pub get
flutter run -d windows
```

Needs the Rust toolchain on PATH (`flutter_vodozemac` builds vodozemac through
cargokit) and MSVC for the Windows build. The first Windows build downloads a
large prebuilt `libwebrtc`.

```
flutter analyze
flutter test
```

## TODO

### 1. Verify screen-share system audio

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

### 2. Verify settings, accounts and verification against Element

Everything in stage 4 is implemented but has only been exercised against
itself. What needs a second client:

1. **The shield is the acceptance test.** Send a message and look at it in
   Element. Before setup it shows "encrypted by a device not verified by its
   owner"; after Settings → Sessions & Security → *Set up encryption* (or *Use
   recovery key*) it must show nothing. That single check is what the whole
   cross-signing path exists for — see "Why Element flags your messages" below.
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

### 3. In the Home menu: Activity Summary
- Users can Follow other users
- In the Home menu there is a list of all people you followed which are currently in voicechannels or have recently typed in text channels.
  - "recent" is defined by a custom set timer via settings
  - each of this features can be turened off individually
- Maybe also a list of recent messages sent in channels by followed people
- every activity can be clicked to bring you directly to the content (connects you to voice call/shows the message in the channel and highlights it)

### second to last Plattform Support
- Linux
- Macos
- iOS
- Android

### last: Smaller things

- Renegotiating the microphone mid-call briefly drops audio for others.
- Matrix device ids change on every logout/login, so per-device volumes are
  forgotten when someone re-authenticates. Inherent to keying by device.
  Switching accounts does **not** lose them: the session is restored from its
  own database rather than re-authenticated, so the device id survives.
- A hard kill (Task Manager) cannot withdraw the call membership; it expires on
  its own after a few hours.

## Accounts and verification

Notes that are expensive to rediscover. Code lives in
`lib/features/accounts/` and `lib/features/settings/`.

### One live client, swapped — not several

`clientProvider` used to be a `ProviderScope` override, and its comment
explained that an override *cannot be rebuilt*, which is what stopped a second
`Client` from opening a second sqlite handle on the same file. Multi-account
made the client genuinely mutable, so that guarantee had to move rather than
disappear: `ActiveClientController` is now the only thing allowed to construct
or dispose a client, and the rule it enforces is that **no two live clients
share a storage key**.

Read sites did not change. `clientProvider` is still a `Provider<Client>`; it
just derives from the controller now. The one rule for callers is the one that
was always implied: `watch` it, never cache it.

### Each account owns a database, and that is where its session lives

Nothing stores an access token. The token is already inside each account's
`MatrixSdkDatabase`, so switching is `Client(storageKey).init()` and the
registry only has to remember which database belongs to whom, plus a cached
display name and avatar so a row can be drawn for an account whose client is
not running.

`matrix_bootstrap.dart` is the only place a storage key becomes a name on disk.
The key `default` maps to the original unsuffixed `matrix_client.sqlite`, which
is what adopts a pre-multi-account installation — the upgrade signs nobody out.
Keys are random rather than sequential so removing an account cannot make the
next one reuse a directory a slow teardown has not finished deleting.

### The order of an account switch is not arbitrary

`AccountActions.switchTo` leaves the call **first**, and awaits it. This cannot
be left to provider disposal: swapping the client rebuilds
`callControllerProvider`, and `LiveKitCallController.dispose` only fires
`unawaited(_teardown(...))` — which races the old client's teardown and loses,
leaving us advertised in a channel we are not in until the membership expires
hours later.

The new client is then built and initialised **before** the old one is
disposed, and only published once it is ready. Two clients coexist for a
moment, which is safe precisely because they are on different databases, and it
means a homeserver that is down leaves the user on the account they had rather
than on nothing.

Note `dispose()`, never `logout()`, when switching. `logout()` calls `clear()`,
which empties the store — switching away from an account would sign you out of
it.

`bootstrapProvider` deliberately watches the *boot* client rather than
`clientProvider`. A swapped-in client has already been initialised, and
re-entering `init()` on it throws `ClientInitPreconditionError` and drops the
whole app to its error screen.

### Verification is off unless `verificationMethods` is set

`KeyVerificationManager` returns early on **every** `m.key.verification.*`
to-device event while `Client.verificationMethods` is empty, which is its
default. Nothing logs anything; incoming requests simply never arrive. The
constructor in `matrix_bootstrap.dart` passes both `emoji` and `numbers`.

### `short_authentication_string` is an intersection, not a choice

This one silently made verification against Element impossible, and looked like
a bug in the protocol rather than in us.

Both sides send every SAS method they know. The SDK keeps the **intersection**
(`_calculatePossibleMethods`), so between two full clients emoji *and* decimal
are both agreed — and each end then independently decides which to draw. Both
derive from the same shared secret, so either is a complete check. Element
leads with emoji. We drew only digits. The result: two people staring at a
seven-emoji row and a twelve-digit number, unable to compare anything, with no
error anywhere because nothing was wrong.

So the dialog shows **one** code, chosen by a preference (Settings → Sessions &
Security → *Verification code*), defaulting to numbers — they are unambiguous
to read aloud, where emoji depend on two people naming the same picture the
same way. When the other end agreed to both, the dialog offers a one-click
switch, because that is the escape hatch for exactly this mismatch.

`resolveSasDisplay` is the rule, and the point of it is that **the preference
cannot override the protocol**: a method the peer never offered is not
renderable, so it falls back rather than showing an empty box. The in-dialog
switch is per-verification and is deliberately not written back — needing to
read someone's emoji once says nothing about which code is easier in general,
and a modal that silently rewrites a setting is a bad way to discover it
changed.

Emoji are rendered with their names underneath for the same reason Element
does: the glyphs differ per platform, and "rabbit" is comparable where two
drawings of a rabbit are not.

### The decimal SAS is twelve digits, and all of them are shown

`KeyVerification.sasNumbers` splits five shared bytes into three 13-bit values
and adds 1000, so it is always three numbers in 1000–9191 — twelve digits,
about 39 bits. There is no six-digit form of this; showing half the digits
would halve the strength of the comparison while looking identical.

We group them as **four groups of three**, Element groups them as three groups
of four. Same digits, read left to right. The dialog says so explicitly,
because a different-looking layout otherwise reads as a mismatch — and
"mismatch" is the one conclusion that must never be reached by accident.

`sas_digits.dart` asserts the input shape rather than regrouping blindly, so an
SDK change that produced something else fails loudly instead of rendering a
short code that still looks checkable.

### Why Element flags your messages: local verification signs nothing

This is the single most misleading thing in the whole feature, and it cost a
release to notice.

Element's per-message shield asks exactly one question: **is this device's key
signed by its owner's self-signing key?** It has not honoured legacy
device-to-device verification for years. So a session can be verified
everywhere in our UI and still be flagged in Element, because "verified" in our
store and "trusted" by everyone else are unrelated facts.

The SDK is explicit about it. `verifyKeysSAS` marks keys with
`setVerified(true, false)` — signing disabled, commented *"we don't want to
sign the keys juuuust yet"* — and publishes a signature only if
`crossSigning.isCached()`. Worse, `Client.isUnknownSession` is literally
`deviceKeys[deviceID]?.signed != true`, so an unsigned session makes the SDK
*skip its own `askSSSS` step* and jump to `done`. The result was a dialog
reporting success while nothing left the machine.

Two consequences are baked into the code now:

- `EncryptionStatus.ownDeviceSigned` is the field that answers "why does
  Element warn about me", and the sessions pane leads with it.
- The verification dialog resolves `signedWithAccountKeys()` before claiming
  anything, and says *"Verified on this device only"* when that is the truth.

### Setting cross-signing up is what makes the client standalone

An account that has only ever used this app has no cross-signing identity at
all, so there is nothing to unlock — it has to be created. `EncryptionSetup`
covers both directions:

- **`createRecovery`** drives the SDK's `Bootstrap` state machine: create a
  recovery key, create the three cross-signing keys, publish them, sign this
  device, turn on the message-key backup. Returns the recovery key, which is
  derived from a private key living only in memory — hence the dialog showing
  it once behind a confirmation checkbox.
- **`signInWithRecoveryKey`** is `crossSigning.selfSign`, for an identity that
  already exists. It unlocks secret storage, caches the keys, and signs *this
  device* with the self-signing key. That signature is the whole fix.

Two things about `Bootstrap` that are not obvious:

- **It hangs without a UIA listener.** Uploading cross-signing keys goes
  through `uiaRequestBackground`, which publishes to `client.onUiaRequest` and
  then waits forever. `_handleUia` answers the password stage; without it there
  is no error, no timeout, and nothing on screen to say why.
- **It never wipes.** Every `askWipe*` state is answered with `false`, and
  `askBadSsss` is turned into an error rather than accepted. Secret storage can
  hold a message-key backup belonging to sessions we know nothing about, and
  overwriting it is not recoverable — not a decision to take inside a wizard.

`enableDehydratedDevices` defaults to false, so the `dehydratedDeviceSetup`
call the bootstrap makes outside its own try/catch is a no-op for us. Worth
knowing before turning that flag on.

### `Size.fromHeight` is an infinite minimum *width*

`FilledButton`'s theme carried `minimumSize: Size.fromHeight(44)`, which reads
as "44 tall" and means `Size(double.infinity, 44)`.

It survived unnoticed for two stages because every button in the app lived in a
`Column(crossAxisAlignment: stretch)`, which hands down a tight width that
clamps the infinity away. The first button placed in a **`Row`** broke: a Row
lays out non-flex children with unbounded main-axis constraints, nothing clamps
it, and layout throws `BoxConstraints forces an infinite width`.

The symptom looks nothing like a button problem. Layout aborts for the whole
subtree, so the pane is never laid out and never painted — a **blank screen**,
followed by a cascade of `RenderBox was not laid out`, `Cannot hit test a render
box with no size`, and mouse-tracker assertions as hit tests walk into
unsized boxes. It presented as "the Sessions tab renders blank", and it looked
intermittent only because that pane draws a spinner (no Row of buttons) until
`encryptionStatusProvider` resolves: the first open laid out fine, the second
had real content and died.

`test/theme/button_theme_test.dart` pins all three cases — a button in a Row, a
button in dialog actions, and the stretched Column that still has to produce a
full-width login button.

### The sync tick must not gate an async provider

`matrixTickProvider` fires every few hundred milliseconds while syncing. Its own
doc says everything else should be a synchronous snapshot derived from `client`
plus a watch on that counter — and every provider in the app follows it except
where this was got wrong once.

Making an **async** provider watch the tick means it is thrown back to
`AsyncLoading` several times a second. Anything rendering it with
`when(loading: …)` then shows a spinner essentially forever. The failure is
delayed and looks unrelated: the pane is correct on first open, because the
provider has just resolved, and blank on every open after, because by then the
tick has moved. That is what made the sessions pane appear to "render blank
after switching tabs".

`sessionsProvider` is therefore a plain `Provider<AsyncValue<…>>` that maps
`deviceListProvider`'s value; only a real `/devices` re-fetch can show a loading
state. `encryptionStatusProvider` has to stay async — `isCached()` awaits — so
it is read with `skipLoadingOnReload: true`.

### Only the requester may send the start

The most expensive bug in this feature, because everything reports success
while the two people are looking at different codes.

The SAS bytes come from an HKDF info string that names the **start** sender
first:

```
MATRIX_KEY_VERIFICATION_SAS|<starter>|<accepter>|<transaction id>
```

The SDK decides that order from `KeyVerification.startedVerification` — which
it sets in `sendRequest()`. So the flag actually means *"we sent the
request"*, and it is only the same thing as *"we sent the start"* when the
requester is also the starter.

Accepting a request and then sending a start breaks precisely that.
`acceptVerification()` leaves us in `askChoice`, and auto-continuing from there
sends a second start — the requester has already sent one. The SDK resolves the
glare by sorting `userId|deviceId` and letting the smaller win. If **our** start
wins we are the starter while the flag still says we are not, so we build the
info string in the opposite order to the other client:

- different SAS bytes → different emoji **and** different digits,
- the MAC at the end fails,
- Element reports *"Your messages are not secure — one of the following may be
  compromised"*, naming the homeserver and the network.

Whether it happens at all depends on how two device ids sort, which is what made
it look intermittent and environmental rather than like a bug in us.

So `_advance` returns early at `askChoice` unless `startedVerification` is true.
That is not a deadlock: with QR unadvertised, `isQrSupported` is false and the
SDK sends the start straight from its own ready handler, without asking the app.
The requester always starts; the accepter always waits. All four combinations of
(who started) × (which client) then agree.

### The states with exactly one sensible answer, and the one without

`askChoice` is auto-answered only on the requesting side, for the reason above.
QR is not advertised, so SAS is the only possibility and there is nothing to put
in front of the user.

`askSSSS` is deliberately **not** auto-answered any more. It used to call
`openSSSS(skip: true)`, which is what produced a green tick here and a warning
in Element with no way to connect the two. It is now a question — enter the
recovery key, or continue knowing the result is local-only.

The SDK calls `onUpdate` again from inside the very calls `_advance` makes, so
it tracks which state it last acted on — without that the auto-continue
re-enters itself and sends the same start event repeatedly. `EncryptionSetup`
guards its `Bootstrap` driver the same way, for the same reason.

## File attachments

Notes that are expensive to rediscover. Code lives in
`lib/features/chat/attachments/`.

### `Room.sendFileEvent`, never `Client.uploadContent`

`uploadContent` uploads **plaintext**. In an encrypted room that ships the file
to the server unprotected, with no error and nothing downstream able to tell.
The SDK's own doc says to use `sendFileEvent` for end-to-end encryption.

`sendFileEvent` also supplies, for free: the local echo, `fileSendingStatus`,
thumbnail generation with separate thumbnail encryption, the `m.upload.size`
pre-check, a retrying upload loop, the cache write that makes
`Event.sendAgain()` work later, and the `EventStatus.error` transition. All of
it arrives through the timeline's existing `onChange → notifyListeners` path,
so the feature added no new state plumbing to `TimelineController`.

### Captions are MSC2530, and the SDK does not expose them directly

`filename` holds the real name, `body` holds the caption when the two differ.
`sendFileEvent` spreads `extraContent` **last** into the event content, so
`extraContent: {'body': caption}` overrides the body while leaving `filename`
intact — exactly the right shape without hand-building content (which would
also mean reimplementing the encrypted-file block).

A caption belongs to *one* file. With several attachments the text is sent as
its own message ahead of them; putting it on the first would make Element render
it as a label for whichever image happened to lead.

### Classification ignores `hasAttachment`

`attachmentKindOf` deliberately switches on msgtype alone. The local echo that
`sendFileEvent` injects has neither `url` nor `file` until the upload finishes,
so gating on `hasAttachment` would render our own image as the text "sent a
picture" for a second and then pop into a thumbnail.

### Encrypted attachments cannot use `Image.network`

`Event.getAttachmentUri()` returns null for an encrypted attachment — the bytes
on the server are ciphertext. That null is the whole branch: when it comes back,
`downloadAndDecryptAttachment()` handles the download, decryption and caching.
One caveat: passing `getThumbnail: true` **throws** when no thumbnail exists,
hence `getThumbnail: event.hasThumbnail`.

### No byte-level upload progress exists

`FileSendingStatus` is a three-value enum (`generatingThumbnail`, `encrypting`,
`uploading`) and neither `sendFileEvent` nor `uploadContent` takes a progress
callback. The UI is indeterminate on purpose; a percentage would be invented.

### Videos we send have no poster frame

`Client.customVideoThumbnailGenerator` is not set and the SDK has no built-in
one, so our own videos render as a placeholder with a play glyph. Videos from
Element carry a thumbnail and do show one. Fixing this means a video decoding
dependency.

### Paste owns `PasteTextIntent`

Intercepting Ctrl+V in a `Focus.onKeyEvent` cannot work: the handler must answer
synchronously and every clipboard read is async. Overriding `PasteTextIntent`
instead also catches the context menu's *Paste* and Shift+Insert, and delegates
back to `EditableText` through `callingAction` when the clipboard holds no
attachment — so selection replacement and undo history stay the framework's job.
The cost is one clipboard round trip on every ordinary text paste.

Regression surface worth re-testing after touching `message_composer.dart`:
paste with a mid-word caret, paste over a selection, the context menu, and
Shift+Insert.

### Drafts are per room, text is not

Attachments staged in one room survive switching away and back, because
`AttachmentDrafts` is a non-autoDispose provider keyed by room id. Typed *text*
is still global — `MessageComposer` carries no `ValueKey(roomId)`, so its state
is reused across rooms. That predates this feature and is left alone
deliberately: adding the key would newly discard typed text on every switch.

### The `device_info_plus` override

`super_native_extensions` caps `device_info_plus` below 12.0.0 while
`livekit_client` requires `^12.3.0`. Without the override in `pubspec.yaml` pub
does **not** fail — it silently backtracks `super_*` to 0.1.x, a three-year-old
release with a different API. See the comment there for why overriding is safe.

If that ever stops being true, the three `attachment_*_source.dart` files are
the only ones that import an input package; `desktop_drop` + `pasteboard` is a
two-file swap. The cost of that route is no iOS support and no virtual files
(an attachment dragged straight out of Outlook or a zip viewer has no path).

## Voice architecture

Notes that are expensive to rediscover.

### MatrixRTC, not the SDK's group calls

The `matrix` Dart SDK ships a VoIP layer, and it is **not usable here**. It
reads and writes `com.famedly.call.member`, a Famedly-only event type that no
Element client understands. Element Call uses `org.matrix.msc3401.call.member`.
The two never see each other.

So this app bypasses the SDK's VoIP layer entirely and speaks MatrixRTC
directly. See `matrix_rtc_membership.dart`.

Consequences worth knowing:

- **Leaving a call is an empty state event, not a redaction.** Most membership
  events in a synced room are `{}` tombstones from people who left. Anything
  that treats "has a state event" as "is in the call" will list everyone who was
  ever in one.
- The state key is `_{userId}_{deviceId}_m.call` (MSC3757 per-device keys).
- `importantStateEvents` in `matrix_bootstrap.dart` must list the membership
  type, or the SDK drops it for any room whose timeline was never opened — and
  the participant list is then permanently empty for exactly the rooms the user
  has not clicked into.

### The LiveKit room name is a hash

`lk-jwt-service` derives it as `SHA256(json([matrixRoomId, slotId]))`. The slot
is the literal string **`m.call#ROOM`** (`kMatrixRtcSlotId`), which is what the
legacy `/sfu/get` endpoint hardcodes. Sending the obvious-looking `m.call`
produces a different hash and lands you alone in an empty room — while the
token, the connection and the publication all report success. Symptom: nobody
hears anybody, and other clients show "waiting for media".

`/sfu/get` is therefore tried **before** `/get_token`, despite being deprecated:
it also assigns the plain-text identity `@user:server:DEVICEID` that Element
matches against Matrix memberships, where `/get_token` uses a hash.

### Device selection is not optional

`livekit_client` does not follow the operating system's default device. Its
`Hardware` singleton picks `devices.firstWhereOrNull(...)` — literally the first
enumerated entry, which on a machine with a virtual audio cable installed is
usually the cable.

Two separate mechanisms are needed, and using only one is a silent half-failure:

- **Output** — `Hardware.selectAudioOutput()`.
- **Input** — `AudioCaptureOptions(deviceId: …)` passed when the track is
  created. `Hardware.selectAudioInput()` alone is *not* enough: capture comes
  from `getUserMedia` constraints, so without a `deviceId` there is no
  constraint and the platform default wins.

### Audio state has one owner

Deafen, per-user local mute and per-user volume are three inputs to one track.
No code path touches a remote track directly; everything changes an input and
calls `_reapplyAudioState()`, which recomputes from all three. This is why
undeafening does not un-mute someone who was individually muted.

It re-runs on every `TrackSubscribedEvent`, which is what makes volumes survive
a peer rejoining — a new track arrives at gain 1.0 and LiveKit carries nothing
across.

Volume is stored **per device**, local mute **per person**: a gain calibrates
one microphone, while muting is a statement about a human.

### Media encryption

LiveKit encrypts frames; Matrix is only the transport that gets the keys to the
right devices. Every participant invents their own 16-byte key, sends it to the
others as an encrypted `io.element.call.encryption_keys` to-device event, and
feeds keys they receive into LiveKit's frame cryptor. See
`call_encryption_manager.dart`.

Two things in here were expensive to find, because **both fail silently**: keys
arrive, indices and identities are right, both ends report `AES-GCM`, and no log
anywhere says anything is wrong.

- **The derivation must be HKDF, not PBKDF2.** The 16 bytes exchanged are only
  key *material*; the AES key is derived from them. LiveKit's web SDK imports
  raw bytes as HKDF material (`createKeyMaterialFromBuffer`) and Element Call
  sets its keys from raw bytes, so it derives with HKDF — while the native
  default is PBKDF2. Same material, different key, nothing decodes.
  `BaseKeyProvider.create()` does not expose the setting at all, which is why
  `createMatrixRtcKeyProvider()` builds `KeyProviderOptions` by hand.
- **A rotated key must be pushed to the running sender.** `E2EEManager` reads
  the key index exactly once, in `_addRtpSender` when a track is published.
  Rotating afterwards stores and distributes the new key while the sender keeps
  encrypting with the old index. Receivers are unaffected — they read the index
  from each frame header — so the symptom is one-directional: you hear everyone,
  nobody hears you.

Everything else:

- Enabled **only when the Matrix room is encrypted**, because everyone else
  follows the same rule — encrypting unilaterally would make us undecodable.
- `keyRingSize` is 255, not the default 16: indices count modulo 256, so a small
  ring makes index 17 overwrite index 1 after enough rotations. (Element passes
  256 to the web SDK; the native implementation documents 1–255.)
- The key is stored under the **LiveKit identity**, while `member.id` in the
  event is our **membershipID**. Identical strings today, different concepts —
  keeping them apart is what stops a future identity change from breaking this
  silently.
- A new key is generated on join and whenever somebody leaves; a mid-call joiner
  is sent the *current* key instead of forcing a rotation. Element additionally
  rotates on join once a grace period has passed. The security-relevant half — a
  departing participant losing access to later media — is implemented, and since
  media is never recorded, a joiner receiving the current key gains nothing
  retroactively.
- Membership changes are coalesced for two seconds before being believed. A
  rejoin is a withdrawal immediately followed by a publish, and participants
  republish as an expiry heartbeat; reacting per event sees people "leave" in
  the gaps. Every spurious rotation costs the whole call five seconds of
  silence.
- The LiveKit identity and the MatrixRTC `memberId` are the same string
  (`@user:server:DEVICEID`), so a key arriving for a member id is handed to
  LiveKit unchanged. This is why the legacy token endpoint matters: its
  plain-text identity is what makes the two line up.
- A received key is only accepted if the claimed member id belongs to the actual
  sender. Without that check any room member could hand us a key attributed to
  someone else and have their stream decoded as that person.
- A new key is published ~5 s before it is used. Encrypting with a key still in
  flight produces a burst of undecodable frames for everyone.
- Keys are never sent to a device whose keys we do not have — such a recipient
  is skipped, not fallen back to plaintext.

### Power levels gate joining

Joining writes `org.matrix.msc3401.call.member`, so it needs permission for that
state event. A fresh Synapse room has `state_default: 50`, making calls
moderator-only until someone adds an `events` entry. `voice_joinability.dart`
classifies this up front so the UI can explain it, and lowering the level
happens only after an explicit confirmation — it is permanent, room-wide and
visible to everyone.

Note room version 12 gives creators implicit power with no entry in `users`.
