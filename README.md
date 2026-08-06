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

1. Voice settings (gear in the user footer) → enable *"Share system audio when
   sharing a screen"*. It is off by default.
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

### 2. Plattform Support
- Linux
- Macos
- iOS
- Android

### 3. Settings
- unified Settings
- Audio settings
- Account Settings
- etc.

### last: Smaller things

- Renegotiating the microphone mid-call briefly drops audio for others.
- Matrix device ids change on every logout/login, so per-device volumes are
  forgotten when someone re-authenticates. Inherent to keying by device.
- A hard kill (Task Manager) cannot withdraw the call membership; it expires on
  its own after a few hours.

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
